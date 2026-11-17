# Changelog

## 1.0.0

Complete rewrite with a new API. Nothing from 0.x is carried over.

- `watch Model, only:, on:, if:, unless:, delivery:, queue: { |record| keys }` replaces `watch` with
  `attributes:`, `keys:`, association names and class-name model inference.
- `delivery :inline | :batched | :async` replaces the `trigger` × `mode` combinations. `:inline` is the default.
- Batching runs on the Rails executor, covering requests, jobs and ActionCable. `CacheSweeperFlushMiddleware` is gone.
  Batches flush early at `max_pending_keys`, and async keys are enqueued in bulk as jobs of `batch_size` keys.
- Async deletion goes through ActiveJob (`CacheSweeper::DeleteJob`) instead of a Sidekiq worker.
- Keys expand like `Rails.cache` keys, so records and composite keys work.
- Sweepers reload with application code in development.
- Logging moved to `ActiveSupport::Notifications` and a `LogSubscriber`. Errors go to `Rails.error`.
- Depends on ActiveRecord, ActiveJob and ActiveSupport 7.1+ instead of all of Rails and `request_store`.
- Requires Ruby 3.3+.

## 0.1.1

- Initial release.
