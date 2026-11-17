# frozen_string_literal: true

require "spec_helper"

RSpec.describe CacheSweeper::Configuration do
  subject(:config) { described_class.new }

  it "has sensible defaults" do
    expect(config).to have_attributes(
      delivery: :inline,
      queue: :default,
      batch_size: 100,
      max_pending_keys: 1_000,
      raise_errors: false,
      force_inline: false,
      sweeper_paths: ["app/sweepers"]
    )
  end

  describe "#cache_store" do
    it "returns the configured store" do
      store = ActiveSupport::Cache::NullStore.new
      config.cache_store = store

      expect(config.cache_store).to be(store)
    end

    it "raises without a configured store outside Rails" do
      expect { config.cache_store }.to raise_error(CacheSweeper::ConfigurationError, /cache_store/)
    end
  end

  describe "#delivery=" do
    it "accepts every delivery mode" do
      CacheSweeper::Delivery::MODES.each do |mode|
        config.delivery = mode
        expect(config.delivery).to eq(mode)
      end
    end

    it "rejects unknown modes" do
      expect { config.delivery = :later }.to raise_error(CacheSweeper::ConfigurationError, /Unknown delivery :later/)
    end
  end

  describe "#queue=" do
    it "accepts symbols and strings" do
      config.queue = :low
      expect(config.queue).to eq(:low)

      config.queue = "high"
      expect(config.queue).to eq("high")
    end

    it "rejects anything else" do
      [nil, 1].each do |queue|
        expect { config.queue = queue }.to raise_error(CacheSweeper::ConfigurationError, /queue must be/)
      end
    end
  end

  %i[batch_size max_pending_keys].each do |setting|
    describe "##{setting}=" do
      it "accepts positive integers" do
        config.public_send(:"#{setting}=", 1)
        expect(config.public_send(setting)).to eq(1)
      end

      it "rejects anything else" do
        [0, -1, 1.5, "10", nil].each do |value|
          message = "#{setting} must be a positive Integer, got #{value.inspect}"
          expect { config.public_send(:"#{setting}=", value) }.to raise_error(CacheSweeper::ConfigurationError, message)
        end
      end
    end
  end
end
