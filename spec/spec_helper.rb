# frozen_string_literal: true

abort "Run the unit and Rails suites separately: bundle exec rake spec" if defined?(Rails)

require "simplecov"
SimpleCov.command_name "unit"
SimpleCov.coverage_dir "coverage/unit"
SimpleCov.start "cache_sweeper"

require "cache_sweeper"
require_relative "support/database"
require_relative "support/rspec"

ActiveJob::Base.queue_adapter = :test
ActiveJob::Base.logger = Logger.new(nil)

RSpec.configure do |config|
  config.before do
    sweeper_config = CacheSweeper::Configuration.new
    sweeper_config.cache_store = ActiveSupport::Cache::MemoryStore.new
    sweeper_config.raise_errors = true
    allow(CacheSweeper).to receive_messages(config: sweeper_config, registry: CacheSweeper::Registry.new)
    enqueued_jobs.clear
  end

  config.after { [Review, Variant, Product].each(&:delete_all) }
end
