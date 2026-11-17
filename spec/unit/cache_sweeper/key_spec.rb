# frozen_string_literal: true

require "spec_helper"

RSpec.describe CacheSweeper::Key do
  let(:product) { Product.create!(name: "Lamp") }

  describe ".expand" do
    it "keeps strings" do
      expect(described_class.expand("products/index")).to eq("products/index")
    end

    it "converts other scalars to params" do
      expect([:index, 1, nil].map { |key| described_class.expand(key) }).to eq(["index", "1", nil])
    end

    it "uses the cache key of objects that have one" do
      expect(described_class.expand(product)).to eq(product.cache_key)
    end

    it "unwraps single-element arrays" do
      expect(described_class.expand(["products"])).to eq("products")
    end

    it "joins multi-element arrays, expanding each part" do
      expect(described_class.expand(["products", product, :card])).to eq("products/#{product.cache_key}/card")
    end

    it "expands nested arrays" do
      expect(described_class.expand(["a", ["b", 1]])).to eq("a/b/1")
    end

    it "sorts hash pairs" do
      expect(described_class.expand({ page: 2, locale: :en })).to eq("locale=en/page=2")
    end
  end

  describe ".list" do
    it "wraps a single key" do
      expect(described_class.list("a")).to eq(["a"])
    end

    it "treats a top-level array as a list of keys" do
      expect(described_class.list(["a", ["b", 1]])).to eq(%w[a b/1])
    end

    it "keeps a hash as one key" do
      expect(described_class.list({ page: 1 })).to eq(["page=1"])
    end

    it "drops blank keys and duplicates after expansion" do
      expect(described_class.list(["a", nil, "", "a", ["a"], ["b", 1], "b/1"])).to eq(%w[a b/1])
    end
  end

  shared_examples "keys the store wrote" do
    {
      "a string" => -> { "products/index" },
      "a record with a suffix" => -> { [product, :card] },
      "a hash" => -> { { locale: :en, page: 1 } },
      "a nested composite" => -> { ["list", product, { page: 1 }] }
    }.each do |description, key_builder|
      it "matches #{description}" do
        key = instance_exec(&key_builder)
        cache.write(key, true)

        CacheSweeper.delete(key)

        expect(cache.exist?(key)).to be(false)
      end
    end
  end

  context "with cache versioning" do
    before { allow(Product).to receive(:cache_versioning).and_return(true) }

    it_behaves_like "keys the store wrote"
  end

  context "without cache versioning" do
    before { allow(Product).to receive(:cache_versioning).and_return(false) }

    it_behaves_like "keys the store wrote"
  end
end
