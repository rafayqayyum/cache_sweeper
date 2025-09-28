# Base class for all sweepers
module CacheSweeper
  class Base
    include CacheSweeper::DSL

    class << self
      # Sweeper-level configuration
      attr_accessor :trigger, :mode, :queue, :sidekiq_options

      # Clean DSL for sweeper configuration
      def sweeper_options(options = {})
        @trigger = options[:trigger] if options.key?(:trigger)
        @mode = options[:mode] if options.key?(:mode)
        @queue = options[:queue] if options.key?(:queue)
        @sidekiq_options = options[:sidekiq_options] if options.key?(:sidekiq_options)
        CacheSweeper.validate_async_mode(@mode, "sweeper #{self.name}")
      end

    end


    # Instance method support for custom conditions
    def call_condition(condition, *args)
      case condition
      when Proc
        instance_exec(*args, &condition)
      when Symbol, String
        send(condition, *args)
      else
        true
      end
    end
  end
end
