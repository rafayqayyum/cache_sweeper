# Example usage of CacheSweeper gem in your main Rails application

# 1. Add to your Gemfile:
# gem 'cache_sweeper', path: '/path/to/cache_sweeper'

# 2. Configure in config/initializers/cache_sweeper.rb:
# Logging configuration
CacheSweeper.configure do |config|
  config.logger = Rails.logger
  config.log_level = :info  # :debug, :info, :warn, :error

  # Cache invalidation configuration (optional - has sensible defaults)
  config.trigger = :request        # :instant or :request
  config.mode = :async             # :async or :inline
  config.queue = :low              # Sidekiq queue name
  config.sidekiq_options = { retry: false }
  config.delete_multi_batch_size = 100  # Batch size for efficient cache deletion
end
name

# 3. Add middleware to config/application.rb (if using request-level batching):
# config.middleware.use CacheSweeperFlushMiddleware

# 4. Create sweeper classes in app/cache_sweepers/:

# app/cache_sweepers/product_sweeper.rb
class ProductSweeper < CacheSweeper::Base
  # Clear cache when name or price changes
  watch attributes: [:name, :price], keys: ->(product) { ["product:#{product.id}"] }

  # Clear cache when product is created, updated, or destroyed
  watch attributes: [:name, :price], keys: ->(product) { ["products:index", "products:featured"] }
end

# app/cache_sweepers/order_sweeper.rb
class OrderSweeper < CacheSweeper::Base
  # Clean DSL for sweeper configuration
  sweeper_options trigger: :request, mode: :async, queue: :orders

  # Clear cache when order status changes
  watch attributes: [:status], keys: ->(order) { ["order:#{order.id}", "user:#{order.user_id}:orders"] }

  # Clear cache when order items change
  watch :order_items, attributes: [:quantity, :price], keys: ->(order_item) {
    ["order:#{order_item.order_id}", "order:#{order_item.order_id}:total"]
  }
end

# app/cache_sweepers/user_sweeper.rb
class UserSweeper < CacheSweeper::Base
  # Clear cache when user profile changes
  watch attributes: [:name, :email], keys: ->(user) { ["user:#{user.id}", "user:#{user.id}:profile"] }

  # Clear cache with custom condition
  watch attributes: [:last_login_at], keys: ->(user) { ["users:active"] },
       if: ->(user) { user.last_login_at_changed? && user.last_login_at > 1.day.ago }
end

# 5. The gem will automatically:
# - Load all sweeper classes from app/cache_sweepers/
# - Attach callbacks to your models
# - Invalidate cache when watched attributes change
# - Handle batching and async processing
