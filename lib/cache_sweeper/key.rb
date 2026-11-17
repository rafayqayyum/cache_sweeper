# frozen_string_literal: true

module CacheSweeper
  # Mirrors ActiveSupport::Cache::Store#expanded_key so swept keys match the keys the store wrote.
  module Key
    class << self
      def list(value)
        Array.wrap(value).map { |key| expand(key) }.compact_blank.uniq
      end

      def expand(key)
        return key.cache_key.to_s if key.respond_to?(:cache_key)

        case key
        when Array then key.many? ? key.map { |part| expand(part) }.to_param : expand(key.first)
        when Hash then key.map { |name, value| "#{name}=#{value}" }.sort!.to_param
        else key.to_param
        end
      end
    end
  end
end
