# frozen_string_literal: true

require "spec_helper"

RSpec.describe CacheSweeper::DeleteJob do
  before { seed_cache("a", "b") }

  it "deletes the given keys" do
    described_class.perform_now(%w[a b])

    expect([cached?("a"), cached?("b")]).to eq([false, false])
  end

  it "deletes the keys after a serialization round trip" do
    ActiveJob::Base.execute(described_class.new(%w[a]).serialize)

    expect([cached?("a"), cached?("b")]).to eq([false, true])
  end

  it "runs on the queue it is enqueued on" do
    described_class.set(queue: :low).perform_later(%w[a])

    expect(enqueued_jobs).to contain_exactly(delete_job(%w[a], queue: :low))
  end

  it "raises cache errors so the queue adapter can retry" do
    CacheSweeper.config.raise_errors = false
    allow(cache).to receive(:delete_multi).and_raise("cache down")

    expect { described_class.perform_now(%w[a]) }.to raise_error("cache down")
  end
end
