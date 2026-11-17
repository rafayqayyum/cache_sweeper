# frozen_string_literal: true

module CacheSweeper
  class DeleteJob < ActiveJob::Base
    def perform(keys)
      CacheSweeper.delete(*keys)
    end
  end
end
