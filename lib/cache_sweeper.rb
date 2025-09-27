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
    sidekiq_options: {}
  }.freeze

  class << self
    attr_accessor :logger, :log_level, :trigger, :mode, :queue, :sidekiq_options

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
  end
end

if defined?(Rails)
  require "cache_sweeper/railtie"
end
