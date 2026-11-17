# frozen_string_literal: true

require "spec_helper"

RSpec.describe CacheSweeper::Dispatcher do
  let!(:product) { Product.create!(name: "Lamp", slug: "lamp", price: 10) }

  context "with an inline sweeper" do
    before do
      define_sweeper("CatalogSweeper") do
        delivery :inline

        watch Product, only: %i[name slug] do |product|
          ["products/#{product.slug}", "products/#{product.slug_before_last_save}", "products/index"]
        end
      end
      seed_cache("products/lamp", "products/desk", "products/index")
    end

    it "sweeps after create" do
      Product.create!(name: "Desk", slug: "desk")

      expect([cached?("products/desk"), cached?("products/index")]).to eq([false, false])
    end

    it "sweeps the keys of the old and new values after a watched update" do
      product.update!(slug: "desk")

      expect(%w[products/lamp products/desk products/index].map { |key| cached?(key) }).to all(be(false))
    end

    it "ignores updates to unwatched attributes" do
      product.update!(price: 20)

      expect(cached?("products/index")).to be(true)
    end

    it "sweeps after destroy, even when the last update skipped the watched attributes" do
      product.update!(price: 20)
      product.destroy!

      expect(cached?("products/lamp")).to be(false)
    end

    it "ignores rolled-back changes" do
      Product.transaction do
        product.update!(name: "Desk")
        raise ActiveRecord::Rollback
      end

      expect(cached?("products/index")).to be(true)
    end

    it "waits for the surrounding transaction to commit" do
      Product.transaction do
        product.update!(name: "Desk")
        expect(cached?("products/index")).to be(true)
      end

      expect(cached?("products/index")).to be(false)
    end
  end

  describe "rule selection" do
    before { seed_cache("catalog", "search", "products/lamp") }

    it "runs every rule watching the model" do
      define_sweeper("CatalogSweeper") { watch(Product) { "catalog" } }
      define_sweeper("SearchSweeper") { watch(Product) { "search" } }

      product.update!(name: "Desk")

      expect([cached?("catalog"), cached?("search")]).to eq([false, false])
    end

    it "sweeps keys of another model from a watched association" do
      variant = product.variants.create!(price: 10)
      define_sweeper { watch(Variant, only: :price) { |variant| "products/#{variant.product.slug}" } }

      variant.update!(price: 20)

      expect(cached?("products/lamp")).to be(false)
    end

    it "only sweeps the watched events" do
      define_sweeper { watch(Product, on: :destroy) { "catalog" } }

      product.update!(name: "Desk")
      expect(cached?("catalog")).to be(true)

      product.destroy!
      expect(cached?("catalog")).to be(false)
    end

    it "applies parent model rules to STI subclasses, once" do
      digital = DigitalProduct.create!(name: "Ebook")
      define_sweeper { watch(Product) { "catalog" } }

      events = instrumented("sweep.cache_sweeper") { digital.update!(name: "Audiobook") }

      expect(events.size).to eq(1)
      expect(cached?("catalog")).to be(false)
    end

    it "applies subclass rules only to the subclass" do
      define_sweeper { watch(DigitalProduct) { "catalog" } }

      product.update!(name: "Desk")

      expect(cached?("catalog")).to be(true)
    end

    it "honours conditions" do
      define_sweeper { watch(Review, if: :published?) { |review| "products/#{review.product.slug}" } }

      Review.create!(product:, published: false)
      expect(cached?("products/lamp")).to be(true)

      Review.create!(product:, published: true)
      expect(cached?("products/lamp")).to be(false)
    end
  end

  describe "delivery" do
    before { seed_cache("catalog", "products/#{product.id}") }

    it "deletes inline by default, even while a batch is open" do
      define_sweeper { watch(Product) { "catalog" } }
      CacheSweeper::Batch.open

      product.update!(name: "Desk")

      expect(cached?("catalog")).to be(false)
    ensure
      CacheSweeper::Batch.close
    end

    it "collects batched keys from several records into one deduplicated delete" do
      other = Product.create!(name: "Desk")
      define_sweeper { delivery :batched }.watch(Product) { |record| ["catalog", "products/#{record.id}"] }

      CacheSweeper::Batch.open
      product.update!(name: "Chair")
      other.update!(name: "Table")
      events = instrumented("delete.cache_sweeper") { CacheSweeper::Batch.close }

      expect(events.map { |event| event.payload[:keys] })
        .to eq([["catalog", "products/#{product.id}", "products/#{other.id}"]])
    end

    it "enqueues async deletions on the sweeper's queue" do
      define_sweeper do
        delivery :async, queue: :low
        watch(Product) { "catalog" }
      end

      product.update!(name: "Desk")

      expect(enqueued_jobs).to contain_exactly(delete_job(["catalog"], queue: :low))
      expect(cached?("catalog")).to be(true)
    end
  end

  describe "instrumentation" do
    it "publishes a sweep event per matching rule" do
      sweeper = define_sweeper do
        delivery :inline
        watch(Product) { "catalog" }
      end

      events = instrumented("sweep.cache_sweeper") { product.update!(name: "Desk") }

      expect(events.map(&:payload))
        .to eq([{ sweeper:, record: product, event: :update, keys: ["catalog"], delivery: :inline }])
    end

    it "skips rules that produce no keys" do
      define_sweeper { watch(Product) { nil } }

      events = instrumented(/cache_sweeper/) { product.update!(name: "Desk") }

      expect(events).to be_empty
    end
  end

  describe "errors" do
    before do
      define_sweeper("BrokenSweeper") { watch(Product, on: :update) { raise "boom" } }
      define_sweeper("WorkingSweeper") do
        delivery :inline
        watch(Product, on: :update) { "catalog" }
      end
      seed_cache("catalog")
    end

    it "raises when raise_errors is enabled" do
      expect { product.update!(name: "Desk") }.to raise_error(RuntimeError, "boom")
    end

    context "when raise_errors is disabled" do
      before do
        CacheSweeper.config.raise_errors = false
        allow(CacheSweeper).to receive(:report).and_call_original
      end

      it "reports the error with context and keeps running the other rules" do
        product.update!(name: "Desk")

        expect(CacheSweeper).to have_received(:report)
          .with(an_instance_of(RuntimeError), sweeper: "BrokenSweeper", model: "Product", record_id: product.id, event: :update)
        expect(cached?("catalog")).to be(false)
      end

      it "keeps the committed change" do
        product.update!(name: "Desk")

        expect(product.reload.name).to eq("Desk")
      end
    end
  end
end
