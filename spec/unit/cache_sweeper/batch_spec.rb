# frozen_string_literal: true

require "spec_helper"

RSpec.describe CacheSweeper::Batch do
  after { described_class.close }

  describe ".current, .open and .close" do
    it "has no batch by default" do
      expect(described_class.current).to be_nil
    end

    it "opens a batch for the current execution context" do
      batch = described_class.open

      expect(described_class.current).to be(batch)
    end

    it "keeps batches isolated per thread" do
      described_class.open

      expect(Thread.new { described_class.current }.value).to be_nil
    end

    it "flushes and discards the batch on close" do
      batch = described_class.open
      allow(batch).to receive(:flush)

      described_class.close

      expect(batch).to have_received(:flush)
      expect(described_class.current).to be_nil
    end

    it "does nothing when closing without a batch" do
      expect(described_class.close).to be_nil
    end
  end

  describe "#flush" do
    subject(:batch) { described_class.new }

    let(:error) { RuntimeError.new("cache down") }

    it "deletes the collected keys in one deduplicated call" do
      seed_cache("a", "b", "c")
      allow(cache).to receive(:delete_multi).and_call_original
      batch.delete(%w[a b])
      batch.delete(%w[b c])

      batch.flush

      expect(cache).to have_received(:delete_multi).once.with(%w[a b c])
      expect(%w[a b c].map { |key| cached?(key) }).to all(be(false))
    end

    it "enqueues one deduplicated job per queue" do
      batch.enqueue(%w[a b], :low)
      batch.enqueue(%w[b c], :low)
      batch.enqueue(%w[d], :high)

      batch.flush

      expect(enqueued_jobs).to contain_exactly(delete_job(%w[a b c], queue: :low), delete_job(%w[d], queue: :high))
    end

    it "splits each queue's keys into jobs of batch_size" do
      CacheSweeper.config.batch_size = 2
      batch.enqueue(%w[a b c], :low)

      batch.flush

      expect(enqueued_jobs).to contain_exactly(delete_job(%w[a b], queue: :low), delete_job(%w[c], queue: :low))
    end

    it "empties the batch so a second flush does nothing" do
      batch.delete(%w[a])
      batch.enqueue(%w[b], :low)
      batch.flush
      seed_cache("a")

      batch.flush

      expect(cached?("a")).to be(true)
      expect(enqueued_jobs.size).to eq(1)
    end

    it "does nothing when empty" do
      allow(cache).to receive(:delete_multi)

      batch.flush

      expect(cache).not_to have_received(:delete_multi)
      expect(enqueued_jobs).to be_empty
    end

    it "raises flush errors when raise_errors is enabled" do
      allow(cache).to receive(:delete_multi).and_raise(error)
      batch.delete(%w[a])

      expect { batch.flush }.to raise_error(error)
    end

    context "when raise_errors is disabled" do
      before do
        CacheSweeper.config.raise_errors = false
        allow(CacheSweeper).to receive(:report)
      end

      it "reports a failed deletion and still enqueues" do
        allow(cache).to receive(:delete_multi).and_raise(error)
        batch.delete(%w[a])
        batch.enqueue(%w[b], :low)

        batch.flush

        expect(CacheSweeper).to have_received(:report).with(error, keys: %w[a])
        expect(enqueued_jobs).to contain_exactly(delete_job(%w[b], queue: :low))
      end

      it "reports a failed enqueue and continues with the other queues" do
        allow(ActiveJob).to receive(:perform_all_later).and_wrap_original do |perform_all_later, jobs|
          jobs.first.queue_name == "low" ? raise(error) : perform_all_later.call(jobs)
        end
        batch.enqueue(%w[a], :low)
        batch.enqueue(%w[b], :high)

        batch.flush

        expect(CacheSweeper).to have_received(:report).with(error, keys: %w[a], queue: :low)
        expect(enqueued_jobs).to contain_exactly(delete_job(%w[b], queue: :high))
      end
    end
  end

  describe "pending key limit" do
    subject(:batch) { described_class.new }

    before do
      CacheSweeper.config.max_pending_keys = 3
      seed_cache("a", "b", "c", "d")
    end

    it "flushes early once deletions and enqueues reach max_pending_keys" do
      batch.delete(%w[a b])
      expect(cached?("a")).to be(true)

      batch.enqueue(%w[c], :low)

      expect([cached?("a"), cached?("b")]).to eq([false, false])
      expect(enqueued_jobs).to contain_exactly(delete_job(%w[c], queue: :low))
    end

    it "counts repeated keys once" do
      batch.delete(%w[a b])
      batch.delete(%w[a b])

      expect(cached?("a")).to be(true)
    end

    it "keeps collecting after an early flush" do
      batch.delete(%w[a b c])
      expect(%w[a b c].map { |key| cached?(key) }).to all(be(false))

      batch.delete(%w[d])
      expect(cached?("d")).to be(true)

      batch.flush

      expect(cached?("d")).to be(false)
    end
  end
end
