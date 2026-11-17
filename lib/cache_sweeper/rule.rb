# frozen_string_literal: true

module CacheSweeper
  class Rule
    EVENTS = %i[create update destroy].freeze
    CONDITIONS = %i[if unless].freeze

    attr_reader :sweeper, :model, :events, :attributes, :conditions, :delivery, :queue, :keys

    def initialize(sweeper:, model:, events:, attributes:, conditions:, delivery:, queue:, keys:)
      @sweeper = sweeper
      @model = validate_model!(model)
      @events = validate_events!(Array(events))
      @attributes = Array(attributes).map(&:to_s).presence
      @conditions = validate_conditions!(conditions)
      @delivery = delivery && Delivery.validate!(delivery, queue:)
      @queue = queue
      @keys = keys || raise(ConfigurationError, "#{sweeper} must pass a block to `watch #{model}` returning the cache keys")
      freeze
    end

    def matches?(record, event)
      events.include?(event) && (event != :update || attributes.nil? || record.saved_changes.keys.intersect?(attributes))
    end

    def keys_for(record)
      instance = sweeper.new
      return [] unless conditions_met?(instance, record)

      Key.list(instance.instance_exec(record, &keys))
    end

    def delivery_mode
      delivery || sweeper.delivery_mode || CacheSweeper.config.delivery
    end

    def queue_name
      queue || sweeper.delivery_queue || CacheSweeper.config.queue
    end

    private

    def conditions_met?(instance, record)
      conditions.all? do |kind, condition|
        result = condition.is_a?(Symbol) ? record.public_send(condition) : instance.instance_exec(record, &condition)
        kind == :if ? result : !result
      end
    end

    def validate_model!(model)
      unless model.is_a?(Class) && model < ActiveRecord::Base && !model.abstract_class?
        raise ConfigurationError, "#{sweeper} can only watch concrete ActiveRecord models, got #{model.inspect}"
      end

      model
    end

    def validate_events!(events)
      unknown = events - EVENTS
      raise ConfigurationError, "#{sweeper} watches unknown events #{unknown.inspect}, expected #{EVENTS.inspect}" if unknown.any?
      raise ConfigurationError, "#{sweeper} must watch at least one of #{EVENTS.inspect}" if events.empty?

      events
    end

    def validate_conditions!(conditions)
      unknown = conditions.keys - CONDITIONS
      raise ConfigurationError, "#{sweeper} passed unknown options #{unknown.inspect} to `watch #{model}`" if unknown.any?

      conditions.each do |kind, condition|
        next if condition.is_a?(Symbol) || condition.is_a?(Proc)

        raise ConfigurationError, "#{sweeper} `#{kind}:` must be a Symbol or Proc, got #{condition.inspect}"
      end
    end
  end
end
