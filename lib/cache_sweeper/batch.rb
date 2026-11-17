# frozen_string_literal: true

module CacheSweeper
  class Batch
    STATE_KEY = :cache_sweeper_batch

    class << self
      def current
        ActiveSupport::IsolatedExecutionState[STATE_KEY]
      end

      def open
        ActiveSupport::IsolatedExecutionState[STATE_KEY] = new
      end

      def close
        ActiveSupport::IsolatedExecutionState.delete(STATE_KEY)&.flush
      end
    end

    def initialize
      reset
    end

    def delete(keys)
      @deletions.merge(keys)
      flush if full?
    end

    def enqueue(keys, queue)
      @enqueues[queue].merge(keys)
      flush if full?
    end

    def flush
      deletions = @deletions.to_a
      enqueues = @enqueues.transform_values(&:to_a)
      reset
      flush_deletions(deletions)
      flush_enqueues(enqueues)
    end

    private

    def reset
      @deletions = Set.new
      @enqueues = Hash.new { |hash, queue| hash[queue] = Set.new }
    end

    def full?
      @deletions.size + @enqueues.sum { |_queue, keys| keys.size } >= CacheSweeper.config.max_pending_keys
    end

    def flush_deletions(keys)
      Delivery::Immediate.delete(keys) if keys.any?
    rescue StandardError => e
      CacheSweeper.report(e, keys:)
    end

    def flush_enqueues(enqueues)
      enqueues.each do |queue, keys|
        Delivery::Immediate.enqueue(keys, queue)
      rescue StandardError => e
        CacheSweeper.report(e, keys:, queue:)
      end
    end
  end
end
