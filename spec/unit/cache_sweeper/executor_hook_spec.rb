# frozen_string_literal: true

require "spec_helper"

RSpec.describe CacheSweeper::ExecutorHook do
  let(:executor) { Class.new(ActiveSupport::Executor).tap { |executor| executor.register_hook(described_class) } }

  before { seed_cache("a") }

  def sweep_batched
    CacheSweeper::Delivery.call(["a"], mode: :batched, queue: :default)
  end

  it "opens a batch for the unit of work and flushes it on completion" do
    executor.wrap do
      expect(CacheSweeper::Batch.current).to be_a(CacheSweeper::Batch)
      sweep_batched
      expect(cached?("a")).to be(true)
    end

    expect(cached?("a")).to be(false)
    expect(CacheSweeper::Batch.current).to be_nil
  end

  it "flushes when the unit of work raises" do
    expect do
      executor.wrap do
        sweep_batched
        raise "request failed"
      end
    end.to raise_error("request failed")

    expect(cached?("a")).to be(false)
  end

  it "shares one batch across nested units of work" do
    executor.wrap do
      outer = CacheSweeper::Batch.current
      executor.wrap do
        expect(CacheSweeper::Batch.current).to be(outer)
        sweep_batched
      end
      expect(cached?("a")).to be(true)
    end

    expect(cached?("a")).to be(false)
  end
end
