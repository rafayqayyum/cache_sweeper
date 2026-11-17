# frozen_string_literal: true

module CacheSweeper
  module ExecutorHook
    class << self
      def run
        Batch.open
      end

      def complete(_batch)
        Batch.close
      end
    end
  end
end
