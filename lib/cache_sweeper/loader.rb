require 'request_store'
require 'set'

module CacheSweeper
  module Loader
    SWEEPER_PATH = 'app/sweepers'.freeze

    class << self
      # Configuration resolution methods
      def resolve_trigger(rule, sweeper)
        rule[:trigger] || sweeper.trigger || CacheSweeper.trigger
      end

      def resolve_mode(rule, sweeper)
        rule[:mode] || sweeper.mode || CacheSweeper.mode
      end

      def resolve_queue(rule, sweeper)
        rule[:queue] || sweeper.queue || CacheSweeper.queue
      end

      def resolve_sidekiq_options(rule, sweeper)
        # Merge options in order of precedence: rule > sweeper > global
        options = CacheSweeper.sidekiq_options.dup
        options.merge!(sweeper.sidekiq_options) if sweeper.sidekiq_options
        options.merge!(rule[:sidekiq_options]) if rule[:sidekiq_options]

        # Add queue to options if specified
        queue = resolve_queue(rule, sweeper)
        options[:queue] = queue if queue && queue != :default

        options
      end
    end

    def self.collect_pending_key(key, sweeper = nil, mode = :request)
      if mode == :request
        RequestStore.store["cache_sweeper_pending_keys_#{sweeper&.name || 'global'}"] ||= Set.new
        RequestStore.store["cache_sweeper_pending_keys_#{sweeper&.name || 'global'}"] << key
      elsif mode == :job
        RequestStore.store["cache_sweeper_job_keys_#{sweeper&.name || 'global'}"] ||= Set.new
        RequestStore.store["cache_sweeper_job_keys_#{sweeper&.name || 'global'}"] << key
      end
    end

    def self.flush_pending_keys(sweeper: nil)
      start_time = Time.current
      sweeper_name = sweeper&.name || 'global'

      CacheSweeper::Logger.log_cache_operations("Flushing pending keys for sweeper: #{sweeper_name}", :debug, {
        sweeper: sweeper_name
      })

      # Flush request-level keys
      request_key = "cache_sweeper_pending_keys_#{sweeper_name}"
      keys = RequestStore.store[request_key]
      if keys&.any?
        deleted_count = 0
        failed_count = 0

        keys.each do |key|
          begin
            if defined?(Rails) && Rails.respond_to?(:cache)
              Rails.cache.delete(key)
              deleted_count += 1
            else
              failed_count += 1
            end
          rescue => e
            CacheSweeper::Logger.log_error(e, {
              key: key,
              sweeper: sweeper_name,
              error_type: 'flush_delete_error'
            })
            failed_count += 1
          end
        end

        CacheSweeper::Logger.log_cache_operations("Flushed request-level keys", :info, {
          sweeper: sweeper_name,
          deleted_count: deleted_count,
          failed_count: failed_count,
          total_keys: keys.length
        })

        RequestStore.store[request_key] = Set.new
      end

      # Flush job-level keys
      job_key = "cache_sweeper_job_keys_#{sweeper_name}"
      job_keys = RequestStore.store[job_key]
      if job_keys&.any?
        begin
          CacheSweeper::AsyncWorker.perform_async(job_keys.to_a)
          CacheSweeper::Logger.log_cache_operations("Scheduled async job for pending keys", :info, {
            sweeper: sweeper_name,
            keys_count: job_keys.length,
            keys: job_keys.to_a
          })
        rescue => e
          CacheSweeper::Logger.log_error(e, {
            sweeper: sweeper_name,
            keys: job_keys.to_a,
            error_type: 'async_job_schedule_error'
          })
        end
        RequestStore.store[job_key] = Set.new
      end

      duration = (Time.current - start_time) * 1000
      CacheSweeper::Logger.log_performance("flush_pending_keys", duration, {
        sweeper: sweeper_name,
        request_keys_flushed: keys&.length || 0,
        job_keys_scheduled: job_keys&.length || 0
      })
    end

    def self.load_sweepers!
      Dir[Rails.root.join(SWEEPER_PATH, '**', '*_sweeper.rb')].each { |file| require_dependency file }
    end

    def self.hook_sweepers!
      start_time = Time.current
      CacheSweeper::Logger.log_initialization("Starting model attachment process")

      sweeper_count = 0
      rule_count = 0
      error_count = 0
      CacheSweeper::Base.descendants.each do |sweeper|
        sweeper_count += 1
        CacheSweeper::Logger.log_initialization("Processing sweeper: #{sweeper.name}", { sweeper: sweeper.name, rule_count: sweeper.cache_sweeper_rules.length })

        sweeper.cache_sweeper_rules.each do |rule|
          rule_count += 1
          association = rule[:association]
          attributes = rule[:attributes]
          condition = rule[:condition]
          keys = rule[:keys]

          begin
            if association.nil?
              model_name = sweeper.name.sub('Sweeper', '')
              model = model_name.constantize
              CacheSweeper::Logger.log_initialization("Attaching direct model callback: #{model_name}", {
                sweeper: sweeper.name,
                model: model_name,
                attributes: attributes,
                callback: rule[:callback] || :after_commit,
                events: rule[:on] || [:create, :update, :destroy]
              })
              attach_callbacks(model, sweeper, attributes, condition, keys, rule)
            else
              parent_model_name = sweeper.name.sub('Sweeper', '')
              parent_model = parent_model_name.constantize
              assoc_reflection = parent_model.reflect_on_association(association)

              unless assoc_reflection
                CacheSweeper::Logger.warn("Association not found: #{parent_model_name}##{association}", {
                  sweeper: sweeper.name,
                  parent_model: parent_model_name,
                  association: association
                })
                next
              end

              assoc_model = assoc_reflection.klass
              CacheSweeper::Logger.log_initialization("Attaching association callback: #{parent_model_name}##{association} -> #{assoc_model.name}", {
                sweeper: sweeper.name,
                parent_model: parent_model_name,
                association: association,
                assoc_model: assoc_model.name,
                attributes: attributes,
                callback: rule[:callback] || :after_commit,
                events: rule[:on] || [:create, :update, :destroy]
              })
              attach_callbacks(assoc_model, sweeper, attributes, condition, keys, rule, parent_model, association)
            end
          rescue NameError => e
            error_count += 1
            CacheSweeper::Logger.log_error(e, {
              sweeper: sweeper.name,
              association: association,
              error_type: 'model_not_found'
            })
            # Model doesn't exist yet, skip for now
            next
          rescue => e
            error_count += 1
            CacheSweeper::Logger.log_error(e, {
              sweeper: sweeper.name,
              association: association,
              error_type: 'attachment_error'
            })
            next
          end
        end
      end

      duration = (Time.current - start_time) * 1000
      CacheSweeper::Logger.log_initialization("Model attachment completed", {
        sweeper_count: sweeper_count,
        rule_count: rule_count,
        error_count: error_count,
        duration_ms: duration.round(3)
      })
    end

    def self.attach_callbacks(model, sweeper, attributes, condition, keys, rule, parent_model = nil, association = nil)
      callback = lambda do |record|
        start_time = Time.current
        sweeper_instance = sweeper.new

        # Log rule execution start
        CacheSweeper::Logger.log_rule_execution(rule, record, 'started', {
          event: record.previous_changes.keys.any? ? 'update' : (record.persisted? ? 'create' : 'destroy'),
          changed_attributes: record.saved_changes.keys
        })

        begin
          # Check attribute changes
          if attributes
            changed = (record.saved_changes.keys.map(&:to_sym) & attributes.map(&:to_sym)).any?
            CacheSweeper::Logger.log_rule_execution(rule, record, "attribute_check: #{changed}", {
              watched_attributes: attributes,
              changed_attributes: record.saved_changes.keys,
              relevant_changes: record.saved_changes.keys.map(&:to_sym) & attributes.map(&:to_sym)
            })
            next unless changed
          end

          # Check condition
          if condition
            condition_result = sweeper_instance.call_condition(condition, record)
            CacheSweeper::Logger.log_rule_execution(rule, record, "condition_check: #{condition_result}", {
              condition: condition.class.name,
              condition_result: condition_result
            })
            next unless condition_result
          end

          # Generate cache keys
          cache_keys = if keys.is_a?(Proc)
            begin
              generated_keys = keys.call(record)
              CacheSweeper::Logger.log_rule_execution(rule, record, "keys_generated", {
                keys_count: Array(generated_keys).length,
                keys: Array(generated_keys)
              })
              generated_keys
            rescue => e
              CacheSweeper::Logger.log_error(e, {
                sweeper: sweeper.name,
                record_class: record.class.name,
                record_id: record.id,
                error_type: 'key_generation_error'
              })
              next
            end
          else
            Array(keys)
          end

          # Execute cache invalidation
          if parent_model && association
            # For association rules, we need to find the parent records
            # that have this record in their association
            parents = parent_model.joins(association).where(association => { id: record.id })
            CacheSweeper::Logger.log_rule_execution(rule, record, "association_processing", {
              parent_count: parents.count,
              association: association
            })
            Array(parents).each do |parent|
              CacheSweeper::Loader.invalidate_cache(cache_keys, record, rule)
            end
          else
            CacheSweeper::Loader.invalidate_cache(cache_keys, record, rule)
          end

          # Log successful completion
          duration = (Time.current - start_time) * 1000
          CacheSweeper::Logger.log_rule_execution(rule, record, "completed", {
            duration_ms: duration.round(3),
            cache_keys_processed: Array(cache_keys).length
          })

        rescue => e
          duration = (Time.current - start_time) * 1000
          CacheSweeper::Logger.log_error(e, {
            sweeper: sweeper.name,
            record_class: record.class.name,
            record_id: record.id,
            duration_ms: duration.round(3),
            error_type: 'rule_execution_error'
          })
        end
      end

      callback_type = rule[:callback] || :after_commit
      events = rule[:on] || [:create, :update, :destroy]
      model.send(callback_type, callback, on: events)
    end

    def self.invalidate_cache(keys, *args, rule)
      start_time = Time.current
      sweeper = rule[:sweeper_class]
      trigger = resolve_trigger(rule, sweeper)
      mode = resolve_mode(rule, sweeper)
      sidekiq_opts = resolve_sidekiq_options(rule, sweeper)

      CacheSweeper::Logger.debug("Cache invalidation started", {
        sweeper: sweeper&.name,
        trigger: trigger,
        mode: mode,
        keys_count: Array(keys).length
      })

      begin
        if trigger == :request
          RequestStore.store[:cache_sweeper_request_pending] ||= []
          RequestStore.store[:cache_sweeper_request_pending] << { keys: keys, mode: mode, sidekiq_options: sidekiq_opts }
          CacheSweeper::Logger.log_cache_operations("Batched for request: #{Array(keys).inspect} (mode: #{mode})", :info, {
            keys: Array(keys),
            mode: mode,
            batch_size: RequestStore.store[:cache_sweeper_request_pending].length
          })
        else
          if mode == :async
            CacheSweeper::AsyncWorker.set(sidekiq_opts).perform_async(keys)
            CacheSweeper::Logger.log_cache_operations("Scheduled async job for: #{Array(keys).inspect}", :info, {
              keys: Array(keys),
              sidekiq_options: sidekiq_opts
            })
          else
            deleted_count = 0
            failed_count = 0

            Array(keys).each do |key|
              begin
                if defined?(Rails) && Rails.respond_to?(:cache)
                  Rails.cache.delete(key)
                  deleted_count += 1
                  CacheSweeper::Logger.log_cache_operations("Deleted instantly: #{key}", :debug, { key: key })
                else
                  CacheSweeper::Logger.log_cache_operations("Rails cache not available for key: #{key}", :warn, { key: key })
                  failed_count += 1
                end
              rescue => e
                CacheSweeper::Logger.log_error(e, {
                  key: key,
                  error_type: 'cache_delete_error'
                })
                failed_count += 1
              end
            end

            CacheSweeper::Logger.log_cache_operations("Instant deletion completed", :info, {
              deleted_count: deleted_count,
              failed_count: failed_count,
              total_keys: Array(keys).length
            })
          end
        end

        duration = (Time.current - start_time) * 1000
        CacheSweeper::Logger.log_performance("cache_invalidation", duration, {
          trigger: trigger,
          mode: mode,
          keys_count: Array(keys).length
        })

      rescue => e
        duration = (Time.current - start_time) * 1000
        CacheSweeper::Logger.log_error(e, {
          sweeper: sweeper&.name,
          trigger: trigger,
          mode: mode,
          keys: Array(keys),
          duration_ms: duration.round(3),
          error_type: 'cache_invalidation_error'
        })
      end
    end
  end
end
