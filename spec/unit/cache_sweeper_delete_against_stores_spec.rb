# frozen_string_literal: true

require "spec_helper"
require "tmpdir"

RSpec.describe CacheSweeper, ".delete" do
  stores = {
    "MemoryStore" => ->(**options) { ActiveSupport::Cache::MemoryStore.new(**options) },
    "FileStore" => ->(**options) { ActiveSupport::Cache::FileStore.new(Dir.mktmpdir("cache_sweeper"), **options) },
    "RedisCacheStore" => lambda do |**options|
      ActiveSupport::Cache::RedisCacheStore.new(url: ENV.fetch("REDIS_URL", "redis://127.0.0.1:6379/15"), **options)
    end,
    "MemCacheStore" => lambda do |**options|
      ActiveSupport::Cache::MemCacheStore.new(ENV.fetch("MEMCACHE_SERVERS", "127.0.0.1:11211"), **options)
    end
  }

  shared_examples "a store CacheSweeper can sweep" do
    let!(:product) { Product.create!(name: "Lamp", slug: "lamp") }

    it "deletes plain, composite, hash and record keys" do
      keys = ["products/index", ["products", 1, :card], { locale: :en, page: 2 }, [product, :card], product]
      keys.each { |key| store.write(key, true) }

      described_class.delete(*keys)

      expect(keys.map { |key| store.exist?(key) }).to all(be(false))
    end

    it "deletes keys the store has to escape or shorten" do
      keys = ["with spaces and\nnewlines", "ünïcödé/ключ", "long/#{'x' * 300}"]
      keys.each { |key| store.write(key, true) }

      described_class.delete(*keys)

      expect(keys.map { |key| store.exist?(key) }).to all(be(false))
    end

    it "leaves other keys alone" do
      store.write("products/index", true)
      store.write("orders/index", true)

      described_class.delete("products/index")

      expect(store.exist?("orders/index")).to be(true)
    end

    it "deletes more keys than fit in one delete_multi call" do
      described_class.config.batch_size = 10
      keys = Array.new(25) { |index| "products/#{index}" }
      keys.each { |key| store.write(key, true) }

      described_class.delete(*keys)

      expect(keys.map { |key| store.exist?(key) }).to all(be(false))
    end

    it "sweeps a committed model change" do
      define_sweeper do
        delivery :inline
        watch(Product, only: :name) { |product| [product, :card] }
      end
      store.write([product, :card], true)

      product.update!(name: "Desk")

      expect(store.exist?([product, :card])).to be(false)
    end

    it "sweeps through an async job" do
      define_sweeper do
        delivery :async
        watch(Product, only: :name) { |product| [product, :card] }
      end
      store.write([product, :card], true)

      product.update!(name: "Desk")
      CacheSweeper::DeleteJob.perform_now(*enqueued_jobs.sole[:args])

      expect(store.exist?([product, :card])).to be(false)
    end
  end

  stores.each do |name, build_store|
    { "without a namespace" => {}, "with a namespace" => { namespace: "tenant" } }.each do |context_name, options|
      context "with #{name} #{context_name}" do
        let(:store) { build_store.call(**options) }

        before do
          unless store.write("cache_sweeper/ping", true)
            raise "#{name} is unreachable" if ENV["REQUIRE_CACHE_SERVERS"]

            skip "#{name} is unreachable"
          end
          store.clear
          described_class.config.cache_store = store
        end

        it_behaves_like "a store CacheSweeper can sweep"
      end
    end
  end
end
