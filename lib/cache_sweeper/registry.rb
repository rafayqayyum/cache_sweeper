# frozen_string_literal: true

module CacheSweeper
  class Registry
    def initialize
      @rules = Hash.new { |hash, model| hash[model] = [] }
    end

    def add(rule)
      base_class = rule.model.base_class
      base_class.include(Callbacks) unless base_class < Callbacks
      @rules[rule.model] << rule
      rule
    end

    def rules_for(model)
      model.ancestors.take_while { |ancestor| ancestor != ActiveRecord::Base }.flat_map { |ancestor| @rules.fetch(ancestor, []) }
    end

    def rules
      @rules.values.flatten
    end

    def clear
      @rules.clear
    end
  end
end
