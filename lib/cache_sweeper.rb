require "cache_sweeper/version"
require "cache_sweeper/dsl"
require "cache_sweeper/base"
require "cache_sweeper/logger"
require "cache_sweeper/loader"
require "cache_sweeper/async_worker"
require "cache_sweeper/flush_middleware"

module CacheSweeper
  class Error < StandardError; end

  DEFAULTS = {
    log_level: :info,
    trigger:   :instant,
    mode:      :inline,
    queue:     :default,
    sidekiq_options: {},
    delete_multi_batch_size: 100
  }.freeze

  class << self
    attr_accessor :logger, :log_level, :trigger, :mode, :queue, :sidekiq_options, :delete_multi_batch_size

    def configure
      yield self
    end

    def configure_defaults
      DEFAULTS.each { |k, v| instance_variable_set("@#{k}", v) }

      if defined?(Rails)
        @log_level =
          if Rails.env.development?
            :debug
          elsif Rails.env.production?
            :warn
          else
            :info
          end
      end
    end

    def log_level=(level)
      valid_levels = %i[debug info warn error]
      unless valid_levels.include?(level)
        raise ArgumentError,
              "Invalid log level: #{level}. Must be one of: #{valid_levels.join(', ')}"
      end
      @log_level = level
    end

    def attached_sweepers
      @attached_sweepers ||= []
    end

    def validate_configuration!
      validate_async_mode(@mode, "global configuration")
    end

    def validate_async_mode(mode, context)
      if mode == :async && !defined?(Sidekiq)
        warn "CacheSweeper Warning: #{context} has mode set to :async but Sidekiq is not available. " \
             "Async jobs will be executed synchronously. " \
             "Add 'gem \"sidekiq\"' to your Gemfile to enable async processing."
      end
    end

  def delete_cache_keys(keys, context = {})
    keys_array = Array(keys)
    return 0 if keys_array.empty?

    batch_size = @delete_multi_batch_size || 100
    deleted_count = 0
    failed_count = 0

    keys_array.each_slice(batch_size) do |batch|
      begin
        Rails.cache.delete_multi(batch)
        deleted_count += batch.length
        CacheSweeper::Logger.log_cache_operations("Deleted batch of #{batch.length} keys", :debug, context.merge({
          batch_size: batch.length,
          keys: batch
        }))
      rescue => e
        failed_count += batch.length
        CacheSweeper::Logger.log_error(e, context.merge({
          batch_size: batch.length,
          keys: batch,
          error_type: 'delete_multi_error'
        }))
      end
    end

    CacheSweeper::Logger.log_cache_operations("Batch deletion completed", :info, context.merge({
      total_keys: keys_array.length,
      deleted_count: deleted_count,
      failed_count: failed_count,
      batch_size: batch_size
    }))

    deleted_count
  end
  end
end

if defined?(Rails)
  require "cache_sweeper/railtie"
end
