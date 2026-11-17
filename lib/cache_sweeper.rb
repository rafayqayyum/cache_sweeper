# frozen_string_literal: true

require "active_record"
require "active_job"
require "active_support"
require "zeitwerk"

loader = Zeitwerk::Loader.for_gem
loader.ignore("#{__dir__}/cache_sweeper/railtie.rb")
loader.setup

module CacheSweeper
  class Error < StandardError; end
  class ConfigurationError < Error; end

  class << self
    def config
      @config ||= Configuration.new
    end

    def configure
      yield config
    end

    def registry
      @registry ||= Registry.new
    end

    def delete(*keys)
      keys = Key.list(keys)
      return if keys.empty?

      ActiveSupport::Notifications.instrument("delete.cache_sweeper", keys:) do
        keys.each_slice(config.batch_size) { |slice| config.cache_store.delete_multi(slice) }
      end
    end

    def report(error, **context)
      raise error if config.raise_errors

      ActiveSupport::Notifications.instrument("failure.cache_sweeper", error:, **context)
      ActiveSupport.error_reporter.report(error, handled: true, source: "cache_sweeper", context:)
    end
  end
end

require_relative "cache_sweeper/railtie" if defined?(Rails::Railtie)
