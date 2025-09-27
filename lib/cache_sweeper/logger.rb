# lib/cache_sweeper/logger.rb
module CacheSweeper
  class Logger
    class << self
      def log(level, message, context = {})
        return unless should_log?(level)

        formatted_message = format_message(message, level, context)
        CacheSweeper.logger.send(level, formatted_message)
      end

      def debug(message, context = {})
        log(:debug, message, context)
      end

      def info(message, context = {})
        log(:info, message, context)
      end

      def warn(message, context = {})
        log(:warn, message, context)
      end

      def error(message, context = {})
        log(:error, message, context)
      end

      def log_initialization(message, context = {})
        info("Initialization: #{message}", context)
      end

      def log_rule_execution(rule, record, result, context = {})
        sweeper_name = rule[:sweeper_class]&.name || 'Unknown'
        model_name = record.class.name
        record_id = record.respond_to?(:id) ? record.id : 'unknown'

        message = "Rule execution: #{sweeper_name} -> #{model_name}##{record_id}"
        context.merge!({
          sweeper: sweeper_name,
          model: model_name,
          record_id: record_id,
          association: rule[:association],
          attributes: rule[:attributes],
          condition_result: result,
          batching_mode: rule[:batching_mode],
          async: rule[:async]
        })

        debug(message, context)
      end

      def log_performance(operation, duration, context = {})
        message = "Performance: #{operation} took #{duration.round(3)}ms"
        context.merge!({
          operation: operation,
          duration_ms: duration.round(3)
        })

        debug(message, context)
      end

      def log_error(error, context = {})
        message = "Error: #{error.class.name}: #{error.message}"
        context.merge!({
          error_class: error.class.name,
          error_message: error.message,
          backtrace: error.backtrace&.first(5)
        })

        error(message, context)
      end

      def log_cache_operations(message, level = :info, context = {})
        log(level, message, context)
      end

      def log_async_jobs(message, level = :info, context = {})
        log(level, message, context)
      end

      def log_middleware(message, level = :info, context = {})
        log(level, message, context)
      end

      private

      def should_log?(level)
        return false unless CacheSweeper.logger

        level_priority = { debug: 0, info: 1, warn: 2, error: 3 }
        current_level_priority = level_priority[CacheSweeper.log_level] || 1
        requested_level_priority = level_priority[level] || 1

        requested_level_priority >= current_level_priority
      end

      def format_message(message, level, context)
        timestamp = Time.current.strftime("%Y-%m-%d %H:%M:%S.%3N")
        context_str = context.any? ? " #{context.inspect}" : ""
        "[CacheSweeper] [#{timestamp}] [#{level.to_s.upcase}] #{message}#{context_str}"
      end
    end
  end
end
