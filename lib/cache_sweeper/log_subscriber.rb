# frozen_string_literal: true

module CacheSweeper
  class LogSubscriber < ActiveSupport::LogSubscriber
    def sweep(event)
      payload = event.payload
      debug do
        "CacheSweeper #{payload[:sweeper]} swept #{payload[:keys].inspect} (#{payload[:delivery]}) " \
          "on #{payload[:event]} of #{payload[:record].class}##{payload[:record].id}"
      end
    end
    subscribe_log_level :sweep, :debug

    def delete(event)
      debug { "CacheSweeper deleted #{event.payload[:keys].inspect} (#{event.duration.round(1)}ms)" }
    end
    subscribe_log_level :delete, :debug

    def failure(event)
      payload = event.payload
      error { "CacheSweeper failed: #{payload[:error].class}: #{payload[:error].message} #{payload.except(:error).inspect}" }
    end
    subscribe_log_level :failure, :error
  end
end
