# frozen_string_literal: true

module CacheSweeper
  class Configuration
    attr_reader :delivery, :queue, :batch_size, :max_pending_keys
    attr_accessor :raise_errors, :force_inline, :sweeper_paths
    attr_writer :cache_store

    def initialize
      @delivery = :inline
      @queue = :default
      @batch_size = 100
      @max_pending_keys = 1_000
      @raise_errors = false
      @force_inline = false
      @sweeper_paths = ["app/sweepers"]
    end

    def cache_store
      @cache_store || rails_cache || raise(ConfigurationError, "Set CacheSweeper.config.cache_store, Rails.cache is unavailable")
    end

    def delivery=(mode)
      @delivery = Delivery.validate!(mode)
    end

    def queue=(name)
      raise ConfigurationError, "queue must be a Symbol or String, got #{name.inspect}" unless name in Symbol | String

      @queue = name
    end

    def batch_size=(size)
      @batch_size = positive_integer!(:batch_size, size)
    end

    def max_pending_keys=(count)
      @max_pending_keys = positive_integer!(:max_pending_keys, count)
    end

    private

    def rails_cache
      Rails.cache if defined?(Rails.cache)
    end

    def positive_integer!(name, value)
      return value if value.is_a?(Integer) && value.positive?

      raise ConfigurationError, "#{name} must be a positive Integer, got #{value.inspect}"
    end
  end
end
