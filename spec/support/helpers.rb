# frozen_string_literal: true

module Helpers
  def define_sweeper(name = "TestSweeper", &body)
    sweeper = stub_const(name, Class.new(CacheSweeper::Base))
    sweeper.class_eval(&body) if body
    sweeper
  end

  def cache
    CacheSweeper.config.cache_store
  end

  def seed_cache(*keys)
    keys.each { |key| cache.write(key, true) }
  end

  def cached?(key)
    cache.exist?(key)
  end

  def enqueued_jobs
    ActiveJob::Base.queue_adapter.enqueued_jobs
  end

  def delete_job(keys, queue:)
    a_hash_including(job: CacheSweeper::DeleteJob, args: [keys], queue: queue.to_s)
  end

  def instrumented(event_name, &)
    events = []
    ActiveSupport::Notifications.subscribed(->(event) { events << event }, event_name, &)
    events
  end
end
