# Sidekiq worker for async cache invalidation
module CacheSweeper
  class AsyncWorker
    if defined?(Sidekiq)
      include Sidekiq::Worker
    end

    def perform(keys)
      start_time = Time.current
      keys_array = Array(keys)

      log_job_start(keys_array)

      deleted_count = 0
      failed_count = 0
      errors = []

      keys_array.each do |key|
        begin
          if defined?(Rails) && Rails.respond_to?(:cache)
            Rails.cache.delete(key)
            deleted_count += 1
            log_cache_deletion(key, :success)
          else
            log_cache_deletion(key, :rails_not_available)
            failed_count += 1
          end
        rescue => e
          log_cache_deletion(key, :error, e)
          errors << { key: key, error: e.message }
          failed_count += 1
        end
      end

      duration = (Time.current - start_time) * 1000
      log_job_completion(keys_array, deleted_count, failed_count, duration, errors)

    rescue => e
      duration = (Time.current - start_time) * 1000
      log_job_error(e, keys_array, duration)
      raise e
    end

    def self.set(opts)
      self
    end

    def self.perform_async(keys)
      if defined?(Sidekiq) && self.ancestors.include?(Sidekiq::Worker)
        log_job_scheduling(keys, :sidekiq)
        super(keys)
      else
        # In test environment or when Sidekiq is not available, perform synchronously
        log_job_scheduling(keys, :synchronous)
        new.perform(keys)
      end
    end

    private

    def log_job_start(keys)
      CacheSweeper::Logger.log_async_jobs("Async job started", :info, {
        job_id: jid,
        keys_count: keys.length,
        keys: keys
      })
    end

    def log_cache_deletion(key, status, error = nil)
      case status
      when :success
        CacheSweeper::Logger.log_async_jobs("Cache deleted: #{key}", :debug, {
          job_id: jid,
          key: key,
          status: 'success'
        })
      when :rails_not_available
        CacheSweeper::Logger.log_async_jobs("Rails cache not available for key: #{key}", :warn, {
          job_id: jid,
          key: key,
          status: 'rails_not_available'
        })
      when :error
        CacheSweeper::Logger.log_error(error, {
          job_id: jid,
          key: key,
          status: 'error',
          error_type: 'cache_delete_error'
        })
      end
    end

    def log_job_completion(keys, deleted_count, failed_count, duration, errors)
      CacheSweeper::Logger.log_async_jobs("Async job completed", :info, {
        job_id: jid,
        keys_count: keys.length,
        deleted_count: deleted_count,
        failed_count: failed_count,
        duration_ms: duration.round(3),
        errors: errors
      })

      CacheSweeper::Logger.log_performance("async_cache_deletion", duration, {
        job_id: jid,
        keys_count: keys.length,
        deleted_count: deleted_count,
        failed_count: failed_count
      })
    end

    def log_job_error(error, keys, duration)
      CacheSweeper::Logger.log_error(error, {
        job_id: jid,
        keys: keys,
        duration_ms: duration.round(3),
        error_type: 'async_job_error'
      })
    end

    def self.log_job_scheduling(keys, method)
      CacheSweeper::Logger.log_async_jobs("Async job scheduled", :info, {
        method: method,
        keys_count: Array(keys).length,
        keys: Array(keys)
      })
    end

    def jid
      @jid ||= SecureRandom.hex(8)
    end
  end
end
