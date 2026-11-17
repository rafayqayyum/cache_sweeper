# frozen_string_literal: true

require "spec_helper"

RSpec.describe CacheSweeper::Registry do
  subject(:registry) { described_class.new }

  let(:sweeper) { define_sweeper }
  let(:widget) { stub_const("Widget", Class.new(TestRecord) { self.table_name = "variants" }) }
  let(:sub_widget) { stub_const("SubWidget", Class.new(widget)) }

  def rule_for(model)
    CacheSweeper::Rule.new(
      sweeper:, model:, events: [:update], attributes: nil, conditions: {}, delivery: nil, queue: nil,
      keys: proc { "key" }
    )
  end

  describe "#add" do
    it "returns the rule" do
      rule = rule_for(Product)

      expect(registry.add(rule)).to be(rule)
    end

    it "installs the commit callbacks on the model's base class" do
      expect { registry.add(rule_for(sub_widget)) }
        .to change { widget.include?(CacheSweeper::Callbacks) }.from(false).to(true)
    end

    it "installs the commit callbacks once per base class" do
      registry.add(rule_for(widget))

      expect do
        registry.add(rule_for(sub_widget))
        registry.add(rule_for(widget))
      end.not_to(change { widget._commit_callbacks.count })
    end
  end

  describe "#rules_for" do
    it "returns the rules of the model and its ancestors" do
      product_rule = registry.add(rule_for(Product))
      digital_rule = registry.add(rule_for(DigitalProduct))

      expect(registry.rules_for(DigitalProduct)).to contain_exactly(product_rule, digital_rule)
      expect(registry.rules_for(Product)).to eq([product_rule])
    end

    it "returns nothing for unwatched models" do
      registry.add(rule_for(Product))

      expect(registry.rules_for(Review)).to eq([])
    end
  end

  describe "#rules" do
    it "lists every registered rule" do
      rules = [registry.add(rule_for(Product)), registry.add(rule_for(Review))]

      expect(registry.rules).to match_array(rules)
    end
  end

  describe "#clear" do
    it "forgets every rule" do
      registry.add(rule_for(Product))
      registry.clear

      expect(registry.rules).to be_empty
    end
  end
end
