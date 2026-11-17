# frozen_string_literal: true

require "spec_helper"

RSpec.describe CacheSweeper::Base do
  describe ".delivery" do
    it "sets the sweeper's delivery mode and queue" do
      sweeper = define_sweeper { delivery :async, queue: :low }

      expect(sweeper).to have_attributes(delivery_mode: :async, delivery_queue: :low)
    end

    it "is unset by default so the global configuration applies" do
      expect(define_sweeper).to have_attributes(delivery_mode: nil, delivery_queue: nil)
    end

    it "is inherited and overridable by subclasses" do
      parent = define_sweeper { delivery :async, queue: :low }
      child = Class.new(parent) { delivery :inline }

      expect(child).to have_attributes(delivery_mode: :inline, delivery_queue: nil)
      expect(Class.new(parent)).to have_attributes(delivery_mode: :async, delivery_queue: :low)
      expect(parent).to have_attributes(delivery_mode: :async, delivery_queue: :low)
    end

    it "rejects unknown modes" do
      expect { define_sweeper { delivery :later } }.to raise_error(CacheSweeper::ConfigurationError, /Unknown delivery/)
    end

    it "rejects a queue without async delivery" do
      expect { define_sweeper { delivery :batched, queue: :low } }
        .to raise_error(CacheSweeper::ConfigurationError, /queue only applies to :async/)
    end
  end

  describe ".watch" do
    it "registers a rule with the given options" do
      keys = ->(product) { "products/#{product.slug}" }
      sweeper = define_sweeper do
        watch(Product, on: :update, only: :name, if: :slug?, delivery: :async, queue: :low, &keys)
      end

      expect(CacheSweeper.registry.rules.sole).to have_attributes(
        sweeper:, model: Product, events: [:update], attributes: ["name"],
        conditions: { if: :slug? }, delivery: :async, queue: :low, keys:
      )
    end

    it "watches every event and attribute by default" do
      define_sweeper { watch(Product) { "products/index" } }

      expect(CacheSweeper.registry.rules.sole)
        .to have_attributes(events: CacheSweeper::Rule::EVENTS, attributes: nil, conditions: {}, delivery: nil, queue: nil)
    end

    it "returns the registered rule" do
      rule = nil
      define_sweeper { rule = watch(Product) { "products/index" } }

      expect(rule).to be(CacheSweeper.registry.rules.sole)
    end
  end
end
