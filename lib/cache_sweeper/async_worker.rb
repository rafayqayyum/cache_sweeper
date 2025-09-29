# Sidekiq worker for async cache invalidation
module CacheSweeper
  class AsyncWorker
    if defined?(Sidekiq)
      include Sidekiq::Worker
    end

    def perform(keys, trigger = :instant)
      start_time = Time.current
      keys_array = Array(keys)
      log_job_start(keys_array, trigger)

      deleted_count = CacheSweeper.delete_cache_keys(keys_array, {
        job_id: jid,
        mode: :async,
        trigger: trigger
      })
      failed_count = keys_array.length - deleted_count

      duration = (Time.current - start_time) * 1000
      log_job_completion(keys_array, deleted_count, failed_count, duration, [], trigger)

    rescue => e
      duration = (Time.current - start_time) * 1000
      log_job_error(e, keys_array, duration, trigger)
      raise e
    end

    def self.perform_async(keys, trigger = :instant)
      if defined?(Sidekiq) && self.ancestors.include?(Sidekiq::Worker)
        log_job_scheduling(keys, :sidekiq, trigger)
        self.set(sidekiq_opts).super(keys, trigger)
      else
        # In test environment or when Sidekiq is not available, perform synchronously
        log_job_scheduling(keys, :synchronous, trigger)
        new.perform(keys, trigger)
      end
    end

    private

    def log_job_start(keys, trigger)
      CacheSweeper::Logger.log_async_jobs("Async job started", :info, {
        job_id: jid,
        keys_count: keys.length,
        keys: keys,
        trigger: trigger
      })
    end

    def log_cache_deletion(keys, status, error = nil)
      case status
      when :success
        CacheSweeper::Logger.log_async_jobs("Cache deleted: #{Array(keys).length} keys", :debug, {
          job_id: jid,
          keys_count: Array(keys).length,
          keys: Array(keys),
          status: 'success'
        })
      when :error
        CacheSweeper::Logger.log_error(error, {
          job_id: jid,
          keys_count: Array(keys).length,
          keys: Array(keys),
          status: 'error',
          error_type: 'cache_delete_error'
        })
      end
    end

    def log_job_completion(keys, deleted_count, failed_count, duration, errors, trigger)
      CacheSweeper::Logger.log_async_jobs("Async job completed", :info, {
        job_id: jid,
        keys_count: keys.length,
        deleted_count: deleted_count,
        failed_count: failed_count,
        duration_ms: duration.round(3),
        errors: errors,
        trigger: trigger
      })

      CacheSweeper::Logger.log_performance("async_cache_deletion", duration, {
        job_id: jid,
        keys_count: keys.length,
        deleted_count: deleted_count,
        failed_count: failed_count,
        trigger: trigger
      })
    end

    def log_job_error(error, keys, duration, trigger)
      CacheSweeper::Logger.log_error(error, {
        job_id: jid,
        keys: keys,
        duration_ms: duration.round(3),
        error_type: 'async_job_error',
        trigger: trigger
      })
    end

    def self.log_job_scheduling(keys, method, trigger)
      CacheSweeper::Logger.log_async_jobs("Async job scheduled", :info, {
        method: method,
        keys_count: Array(keys).length,
        keys: Array(keys),
        trigger: trigger
      })
    end

    def jid
      @jid ||= SecureRandom.hex(8)
    end
  end
end
