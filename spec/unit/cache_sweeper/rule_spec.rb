# frozen_string_literal: true

require "spec_helper"

RSpec.describe CacheSweeper::Rule do
  let(:sweeper) do
    define_sweeper("CatalogSweeper") do
      private

      def helper_key(product) = "helper/#{product.slug}"

      def featured?(product) = product.price.to_i > 100
    end
  end
  let(:product) { Product.create!(name: "Lamp", slug: "lamp", price: 150) }

  def build_rule(**options)
    defaults = {
      sweeper:, model: Product, events: described_class::EVENTS, attributes: nil,
      conditions: {}, delivery: nil, queue: nil, keys: ->(record) { "products/#{record.id}" }
    }
    described_class.new(**defaults, **options)
  end

  describe "validation" do
    {
      "a class that isn't a model" => [{ model: String }, /can only watch concrete ActiveRecord models, got String/],
      "a model name instead of the class" => [{ model: "Product" }, /got "Product"/],
      "an abstract model" => [{ model: TestRecord }, /got TestRecord/],
      "unknown events" => [{ events: %i[save] }, /watches unknown events \[:save\]/],
      "no events" => [{ events: [] }, /must watch at least one of/],
      "a missing keys block" => [{ keys: nil }, /must pass a block to `watch Product`/],
      "unknown options" => [{ conditions: { iff: :slug? } }, /passed unknown options \[:iff\]/],
      "a condition that isn't a Symbol or Proc" => [{ conditions: { if: "slug?" } }, /`if:` must be a Symbol or Proc/],
      "an unknown delivery" => [{ delivery: :later }, /Unknown delivery :later/],
      "a queue without async delivery" => [{ delivery: :batched, queue: :low }, /queue only applies to :async/]
    }.each do |description, (options, message)|
      it "rejects #{description}" do
        expect { build_rule(**options) }.to raise_error(CacheSweeper::ConfigurationError, message)
      end
    end

    it "names the sweeper in errors" do
      expect { build_rule(events: []) }.to raise_error(CacheSweeper::ConfigurationError, /\ACatalogSweeper /)
    end
  end

  describe "normalization" do
    it "accepts a single event" do
      expect(build_rule(events: :update).events).to eq([:update])
    end

    it "stringifies watched attributes" do
      expect(build_rule(attributes: %i[name slug]).attributes).to eq(%w[name slug])
      expect(build_rule(attributes: :name).attributes).to eq(["name"])
    end

    it "treats empty attributes as any attribute" do
      expect(build_rule(attributes: []).attributes).to be_nil
    end

    it "is frozen" do
      expect(build_rule).to be_frozen
    end
  end

  describe "#matches?" do
    it "matches only the watched events" do
      rule = build_rule(events: :destroy)

      expect(rule.matches?(product, :create)).to be(false)
      expect(rule.matches?(product, :destroy)).to be(true)
    end

    it "matches every update without watched attributes" do
      product.update!(price: 10)

      expect(build_rule.matches?(product, :update)).to be(true)
    end

    context "with watched attributes" do
      let(:rule) { build_rule(attributes: :name) }

      it "matches updates that change a watched attribute" do
        product.update!(name: "Desk")

        expect(rule.matches?(product, :update)).to be(true)
      end

      it "ignores updates that only change other attributes" do
        product.update!(price: 10)

        expect(rule.matches?(product, :update)).to be(false)
      end

      it "always matches creates and destroys, whatever changed" do
        record = Product.create!(price: 1)
        expect(rule.matches?(record, :create)).to be(true)

        record.update!(price: 2)
        record.destroy!
        expect(rule.matches?(record, :destroy)).to be(true)
      end
    end
  end

  describe "#keys_for" do
    it "runs the block on a sweeper instance with the record" do
      rule = build_rule(keys: ->(record) { [helper_key(record), [record, :card]] })

      expect(rule.keys_for(product)).to eq(["helper/lamp", "#{product.cache_key}/card"])
    end

    it "normalizes the returned keys" do
      rule = build_rule(keys: ->(_record) { ["a", nil, "a", ["b", 1]] })

      expect(rule.keys_for(product)).to eq(%w[a b/1])
    end

    context "with conditions" do
      let(:unpublished) { Product.create!(name: "Draft", price: 50) }

      it "requires an if: symbol to be truthy on the record" do
        rule = build_rule(conditions: { if: :slug? })

        expect(rule.keys_for(product)).to eq(["products/#{product.id}"])
        expect(rule.keys_for(unpublished)).to eq([])
      end

      it "runs an if: proc on the sweeper with the record" do
        rule = build_rule(conditions: { if: ->(record) { featured?(record) } })

        expect(rule.keys_for(product)).to eq(["products/#{product.id}"])
        expect(rule.keys_for(unpublished)).to eq([])
      end

      it "inverts unless: conditions" do
        expect(build_rule(conditions: { unless: :slug? }).keys_for(product)).to eq([])
        expect(build_rule(conditions: { unless: ->(record) { featured?(record) } }).keys_for(unpublished))
          .to eq(["products/#{unpublished.id}"])
      end

      it "requires every condition to pass" do
        rule = build_rule(conditions: { if: :slug?, unless: ->(record) { featured?(record) } })

        expect(rule.keys_for(product)).to eq([])
      end
    end
  end

  describe "#delivery_mode and #queue_name" do
    it "fall back to the global configuration" do
      expect(build_rule).to have_attributes(delivery_mode: :inline, queue_name: :default)
    end

    it "prefer the sweeper's delivery" do
      sweeper.delivery :async, queue: :low

      expect(build_rule).to have_attributes(delivery_mode: :async, queue_name: :low)
    end

    it "prefer the rule's own options" do
      sweeper.delivery :inline

      expect(build_rule(delivery: :async, queue: :high)).to have_attributes(delivery_mode: :async, queue_name: :high)
    end
  end
end
