# frozen_string_literal: true

require "spec_helper"

RSpec.describe CacheSweeper::Delivery do
  describe ".validate!" do
    it "returns known modes" do
      described_class::MODES.each { |mode| expect(described_class.validate!(mode)).to eq(mode) }
    end

    it "accepts a queue for async delivery" do
      expect(described_class.validate!(:async, queue: :low)).to eq(:async)
    end

    it "rejects unknown modes" do
      expect { described_class.validate!("inline") }.to raise_error(CacheSweeper::ConfigurationError, /Unknown delivery "inline"/)
    end

    it "rejects a queue for other modes" do
      %i[inline batched].each do |mode|
        expect { described_class.validate!(mode, queue: :low) }
          .to raise_error(CacheSweeper::ConfigurationError, /queue only applies to :async delivery, got :#{mode}/)
      end
    end
  end

  describe ".call" do
    let(:keys) { %w[a b] }

    before { seed_cache(*keys) }

    context "without an open batch" do
      it "deletes inline keys immediately" do
        described_class.call(keys, mode: :inline, queue: :default)

        expect(keys.map { |key| cached?(key) }).to all(be(false))
      end

      it "deletes batched keys immediately" do
        described_class.call(keys, mode: :batched, queue: :default)

        expect(keys.map { |key| cached?(key) }).to all(be(false))
      end

      it "enqueues async keys immediately" do
        described_class.call(keys, mode: :async, queue: :low)

        expect(enqueued_jobs).to contain_exactly(delete_job(keys, queue: :low))
        expect(cached?("a")).to be(true)
      end

      it "splits async keys into jobs of batch_size" do
        CacheSweeper.config.batch_size = 1

        described_class.call(keys, mode: :async, queue: :low)

        expect(enqueued_jobs).to contain_exactly(delete_job(%w[a], queue: :low), delete_job(%w[b], queue: :low))
      end
    end

    context "with an open batch" do
      before { CacheSweeper::Batch.open }
      after { CacheSweeper::Batch.close }

      it "still deletes inline keys immediately" do
        described_class.call(keys, mode: :inline, queue: :default)

        expect(cached?("a")).to be(false)
      end

      it "defers batched keys until the batch closes" do
        described_class.call(keys, mode: :batched, queue: :default)
        expect(cached?("a")).to be(true)

        CacheSweeper::Batch.close
        expect(cached?("a")).to be(false)
      end

      it "defers async keys until the batch closes" do
        described_class.call(keys, mode: :async, queue: :low)
        expect(enqueued_jobs).to be_empty

        CacheSweeper::Batch.close
        expect(enqueued_jobs).to contain_exactly(delete_job(keys, queue: :low))
      end
    end

    context "with force_inline" do
      before do
        CacheSweeper.config.force_inline = true
        CacheSweeper::Batch.open
      end

      after { CacheSweeper::Batch.close }

      it "deletes immediately whatever the declared delivery" do
        %i[batched async].each do |mode|
          seed_cache(*keys)
          described_class.call(keys, mode:, queue: :low)

          expect(cached?("a")).to be(false)
        end
        expect(enqueued_jobs).to be_empty
      end
    end
  end
end
