# frozen_string_literal: true

module CacheSweeper
  class Base
    class_attribute :delivery_mode, :delivery_queue, instance_accessor: false

    class << self
      def delivery(mode, queue: nil)
        Delivery.validate!(mode, queue:)
        self.delivery_mode = mode
        self.delivery_queue = queue
      end

      def watch(model, on: Rule::EVENTS, only: nil, delivery: nil, queue: nil, **conditions, &keys)
        CacheSweeper.registry.add(
          Rule.new(sweeper: self, model:, events: on, attributes: only, conditions:, delivery:, queue:, keys:)
        )
      end
    end
  end
end
