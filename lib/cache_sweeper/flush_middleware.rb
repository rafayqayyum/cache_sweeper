require 'request_store'

# Middleware to flush pending cache keys at the end of each request if batching is enabled
class CacheSweeperFlushMiddleware
  def initialize(app)
    @app = app
  end

  def call(env)
    start_time = Time.current
    request_id = SecureRandom.hex(8)

    log_request_start(request_id, env)

    status, headers, response = @app.call(env)

    # At end of request, flush all request-level batched keys
    pending = RequestStore.store[:cache_sweeper_request_pending] || []

    if pending.any?
      log_request_flush_start(request_id, pending)

      async_jobs_scheduled = 0
      instant_deletions = 0
      failed_deletions = 0
      errors = []

      pending.each do |entry|
        keys, mode, sidekiq_options = entry.values_at(:keys, :mode, :sidekiq_options)

        begin
          if mode == :async
            CacheSweeper::AsyncWorker.set(sidekiq_options || {}).perform_async(keys, :request)
            async_jobs_scheduled += 1
            log_batch_processing(request_id, keys, :async_scheduled, sidekiq_options)
          else
            deleted_count = CacheSweeper.delete_cache_keys(keys, {
              request_id: request_id,
              mode: :inline,
              trigger: :request
            })
            instant_deletions += deleted_count
            failed_deletions += Array(keys).length - deleted_count
          end
        rescue => e
          errors << { keys: keys, error: e.message }
          log_batch_processing(request_id, keys, :batch_error, sidekiq_options, e)
        end
      end

      log_request_flush_completion(request_id, {
        total_batches: pending.length,
        async_jobs_scheduled: async_jobs_scheduled,
        instant_deletions: instant_deletions,
        failed_deletions: failed_deletions,
        errors: errors
      })
    else
      log_request_no_flush(request_id)
    end

    [status, headers, response]
  rescue => e
    duration = (Time.current - start_time) * 1000
    log_request_error(request_id, e, duration)
    raise e
  ensure
    RequestStore.store[:cache_sweeper_request_pending] = []
    duration = (Time.current - start_time) * 1000
    log_request_completion(request_id, duration)
  end

  private

  def log_request_start(request_id, env)
    CacheSweeper::Logger.log_middleware("Request started", :debug, {
      request_id: request_id,
      method: env['REQUEST_METHOD'],
      path: env['PATH_INFO']
    })
  end

  def log_request_flush_start(request_id, pending)
    total_keys = pending.sum { |entry| Array(entry[:keys]).length }
    async_count = pending.count { |entry| entry[:async] }
    instant_count = pending.length - async_count

    CacheSweeper::Logger.log_middleware("Request flush started", :info, {
      request_id: request_id,
      batch_count: pending.length,
      total_keys: total_keys,
      async_batches: async_count,
      instant_batches: instant_count
    })
  end

  def log_batch_processing(request_id, keys, status, sidekiq_options = nil, error = nil)
    case status
    when :async_scheduled
      CacheSweeper::Logger.log_middleware("Batch scheduled async", :debug, {
        request_id: request_id,
        keys: Array(keys),
        sidekiq_options: sidekiq_options
      })
    when :error
      CacheSweeper::Logger.log_error(error, {
        request_id: request_id,
        keys: Array(keys),
        error_type: 'batch_processing_error'
      })
    when :batch_error
      CacheSweeper::Logger.log_error(error, {
        request_id: request_id,
        keys: Array(keys),
        sidekiq_options: sidekiq_options,
        error_type: 'batch_error'
      })
    end
  end

  def log_request_flush_completion(request_id, stats)
    CacheSweeper::Logger.log_middleware("Request flush completed", :info, {
      request_id: request_id,
      **stats
    })
  end

  def log_request_no_flush(request_id)
    CacheSweeper::Logger.log_middleware("No cache flush needed", :debug, {
      request_id: request_id
    })
  end

  def log_request_error(request_id, error, duration)
    CacheSweeper::Logger.log_error(error, {
      request_id: request_id,
      duration_ms: duration.round(3),
      error_type: 'middleware_error'
    })
  end

  def log_request_completion(request_id, duration)
    CacheSweeper::Logger.log_performance("request_processing", duration, {
      request_id: request_id
    })
  end
end
