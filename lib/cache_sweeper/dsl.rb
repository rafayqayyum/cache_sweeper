# lib/cache_sweeper/dsl.rb
module CacheSweeper
  module DSL
    def self.included(base)
      base.extend ClassMethods
    end

    module ClassMethods
      def watch(association = nil, attributes: nil, if: nil, keys: nil, trigger: nil, mode: nil, queue: nil, sidekiq_options: nil, callback: nil, on: nil)
        @cache_sweeper_rules ||= []
        @cache_sweeper_rules << {
          association: association,
          attributes: attributes,
          condition: binding.local_variable_get(:if),
          keys: keys,
          trigger: trigger,
          mode: mode,
          queue: queue,
          sidekiq_options: sidekiq_options,
          callback: callback,
          on: on,
          sweeper_class: self
        }
      end

      def cache_sweeper_rules
        @cache_sweeper_rules || []
      end
    end
  end
end
