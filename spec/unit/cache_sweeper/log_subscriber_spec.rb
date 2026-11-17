# frozen_string_literal: true

require "spec_helper"

RSpec.describe CacheSweeper::LogSubscriber do
  subject(:subscriber) { described_class.new }

  let(:output) { StringIO.new }

  before { allow(ActiveSupport::LogSubscriber).to receive(:logger).and_return(ActiveSupport::Logger.new(output)) }

  def event(name, payload)
    ActiveSupport::Notifications::Event.new("#{name}.cache_sweeper", 1.0, 1.0025, "id", payload)
  end

  it "logs sweeps" do
    product = Product.create!(name: "Lamp")

    subscriber.sweep(event("sweep", sweeper: define_sweeper("CatalogSweeper"), record: product, event: :update,
                                    keys: ["products/index"], delivery: :batched))

    expect(output.string)
      .to eq("CacheSweeper CatalogSweeper swept [\"products/index\"] (batched) on update of Product##{product.id}\n")
  end

  it "logs deletions with their duration" do
    subscriber.delete(event("delete", keys: %w[a b]))

    expect(output.string).to eq("CacheSweeper deleted [\"a\", \"b\"] (2.5ms)\n")
  end

  it "logs failures with their context" do
    subscriber.failure(event("failure", error: RuntimeError.new("boom"), sweeper: "CatalogSweeper"))

    expect(output.string).to start_with("CacheSweeper failed: RuntimeError: boom {").and include("CatalogSweeper")
  end
end
