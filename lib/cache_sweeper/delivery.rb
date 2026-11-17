# frozen_string_literal: true

module CacheSweeper
  module Delivery
    MODES = %i[inline batched async].freeze

    class << self
      def validate!(mode, queue: nil)
        raise ConfigurationError, "Unknown delivery #{mode.inspect}, expected one of #{MODES.inspect}" unless MODES.include?(mode)
        raise ConfigurationError, "queue only applies to :async delivery, got #{mode.inspect}" if queue && mode != :async

        mode
      end

      def call(keys, mode:, queue:)
        return CacheSweeper.delete(*keys) if mode == :inline || CacheSweeper.config.force_inline

        target = Batch.current || Immediate
        mode == :async ? target.enqueue(keys, queue) : target.delete(keys)
      end
    end

    module Immediate
      class << self
        def delete(keys)
          CacheSweeper.delete(*keys)
        end

        def enqueue(keys, queue)
          jobs = keys.each_slice(CacheSweeper.config.batch_size).map { |slice| DeleteJob.new(slice).set(queue:) }
          ActiveJob.perform_all_later(jobs)
        end
      end
    end
  end
end
