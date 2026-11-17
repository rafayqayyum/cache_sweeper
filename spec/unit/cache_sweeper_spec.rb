# frozen_string_literal: true

require "spec_helper"

RSpec.describe CacheSweeper do
  it "has a semantic version" do
    expect(CacheSweeper::VERSION).to match(/\A\d+\.\d+\.\d+\z/)
  end

  it "does not load the Railtie without Rails" do
    expect(defined?(CacheSweeper::Railtie)).to be_nil
  end

  describe ".config" do
    before { allow(described_class).to receive(:config).and_call_original }

    it "memoizes a Configuration" do
      expect(described_class.config).to be_a(CacheSweeper::Configuration).and be(described_class.config)
    end
  end

  describe ".configure" do
    it "yields the configuration" do
      expect { |block| described_class.configure(&block) }.to yield_with_args(described_class.config)
    end
  end

  describe ".registry" do
    before { allow(described_class).to receive(:registry).and_call_original }

    it "memoizes a Registry" do
      expect(described_class.registry).to be_a(CacheSweeper::Registry).and be(described_class.registry)
    end
  end

  describe ".delete" do
    before { seed_cache("a", "b/1", "c") }

    it "deletes every given key, expanding composite keys" do
      described_class.delete("a", ["b", 1])

      expect(%w[a b/1 c].map { |key| cached?(key) }).to eq([false, false, true])
    end

    it "deletes in slices of batch_size" do
      described_class.config.batch_size = 2
      allow(cache).to receive(:delete_multi).and_call_original

      described_class.delete("a", "b/1", "c")

      expect(cache).to have_received(:delete_multi).with(%w[a b/1]).ordered
      expect(cache).to have_received(:delete_multi).with(["c"]).ordered
    end

    it "instruments the deletion with the expanded, deduplicated keys" do
      events = instrumented("delete.cache_sweeper") { described_class.delete("a", ["b", 1], "a") }

      expect(events.map(&:payload)).to eq([{ keys: %w[a b/1] }])
    end

    it "does nothing without keys" do
      allow(cache).to receive(:delete_multi)

      events = instrumented("delete.cache_sweeper") { described_class.delete(nil, "", []) }

      expect(events).to be_empty
      expect(cache).not_to have_received(:delete_multi)
    end
  end

  describe ".report" do
    let(:error) { RuntimeError.new("boom") }

    it "raises when raise_errors is enabled" do
      expect { described_class.report(error, sweeper: "CatalogSweeper") }.to raise_error(error)
    end

    context "when raise_errors is disabled" do
      before { described_class.config.raise_errors = false }

      it "reports the error to the Rails error reporter" do
        allow(ActiveSupport.error_reporter).to receive(:report)

        described_class.report(error, sweeper: "CatalogSweeper")

        expect(ActiveSupport.error_reporter).to have_received(:report)
          .with(error, handled: true, source: "cache_sweeper", context: { sweeper: "CatalogSweeper" })
      end

      it "instruments the failure" do
        events = instrumented("failure.cache_sweeper") { described_class.report(error, sweeper: "CatalogSweeper") }

        expect(events.map(&:payload)).to eq([{ error:, sweeper: "CatalogSweeper" }])
      end
    end
  end
end
