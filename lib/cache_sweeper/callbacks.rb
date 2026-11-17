# frozen_string_literal: true

module CacheSweeper
  module Callbacks
    extend ActiveSupport::Concern

    included do
      Rule::EVENTS.each do |event|
        after_commit -> { Dispatcher.call(self, event) }, on: event
      end
    end
  end
end
