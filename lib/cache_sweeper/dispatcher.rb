# frozen_string_literal: true

module CacheSweeper
  module Dispatcher
    class << self
      def call(record, event)
        CacheSweeper.registry.rules_for(record.class).each { |rule| dispatch(rule, record, event) }
      end

      private

      def dispatch(rule, record, event)
        return unless rule.matches?(record, event)

        keys = rule.keys_for(record)
        return if keys.empty?

        payload = { sweeper: rule.sweeper, record:, event:, keys:, delivery: rule.delivery_mode }
        ActiveSupport::Notifications.instrument("sweep.cache_sweeper", payload) do
          Delivery.call(keys, mode: rule.delivery_mode, queue: rule.queue_name)
        end
      rescue StandardError => e
        CacheSweeper.report(e, sweeper: rule.sweeper.name, model: record.class.name, record_id: record.id, event:)
      end
    end
  end
end
