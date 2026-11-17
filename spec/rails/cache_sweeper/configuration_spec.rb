# frozen_string_literal: true

require "rails_helper"

RSpec.describe CacheSweeper::Configuration do
  subject(:config) { described_class.new }

  describe "#cache_store" do
    it "defaults to Rails.cache" do
      expect(config.cache_store).to be(Rails.cache)
    end

    it "raises while Rails.cache is unset" do
      allow(Rails).to receive(:cache).and_return(nil)

      expect { config.cache_store }.to raise_error(CacheSweeper::ConfigurationError, /Rails.cache is unavailable/)
    end
  end
end
