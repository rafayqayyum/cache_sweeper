# CacheSweeper

A flexible, rule-based cache invalidation gem for Rails applications. CacheSweeper enables you to define cache invalidation logic in dedicated sweeper classes, keeping your models clean and your cache logic organized. It supports batching, async jobs via Sidekiq, and association-aware cache sweeping with comprehensive logging.

## Table of Contents

- [Features](#features)
- [Installation](#installation)
- [Quick Start](#quick-start)
- [Configuration](#configuration)
- [Usage Examples](#usage-examples)
- [API Reference](#api-reference)
- [Logging](#logging)
- [Middleware](#middleware)
- [Testing](#testing)
- [Troubleshooting](#troubleshooting)
- [Contributing](#contributing)
- [License](#license)

## Features

- **Rule-based cache invalidation**: Define what changes should trigger cache clearing using a simple DSL
- **Flexible triggering**: Choose between instant cache deletion or request-level batching
- **Async processing**: Offload cache deletion to Sidekiq for scalability
- **Association support**: Invalidate cache for associated models when their attributes change
- **Multi-level configuration**: Control behavior globally, per-sweeper, or per-rule
- **Comprehensive logging**: Detailed logging for debugging with configurable levels
- **Performance monitoring**: Built-in performance logging for cache operations and timing
- **Error tracking**: Comprehensive error logging with context and stack traces
- **Clean model code**: Keep cache logic out of your models
- **Thread-safe**: Uses RequestStore for reliable multi-threaded operation
- **Efficient batch deletion**: Uses `Rails.cache.delete_multi` for optimal performance
- **Configurable batch sizes**: Control how many keys are deleted in each batch

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'cache_sweeper', path: 'path/to/cache_sweeper'
```

Then run:

```sh
bundle install
```

### Dependencies

- **Rails**: 5.0+ (tested with Rails 6.x and 7.x)
- **Sidekiq**: Required for async cache deletion
- **RequestStore**: For thread-safe request-level storage


## Quick Start

### 1. Configure the Gem

Create `config/initializers/cache_sweeper.rb`:

```ruby
# Logging configuration
CacheSweeper.logger = Rails.logger
CacheSweeper.log_level = :info  # :debug, :info, :warn, :error

# Global cache invalidation configuration (optional)
CacheSweeper.trigger = :request        # :instant or :request
CacheSweeper.mode = :async             # :async or :inline
CacheSweeper.queue = :low              # Sidekiq queue name
CacheSweeper.sidekiq_options = { retry: false }
CacheSweeper.delete_multi_batch_size = 100  # Batch size for efficient cache deletion
```

### 2. Add Middleware (if using request-level batching)

Add to `config/application.rb`:

```ruby
config.middleware.use CacheSweeperFlushMiddleware
```

### 3. Create Your First Sweeper

Create `app/cache_sweepers/product_sweeper.rb`:

```ruby
class ProductSweeper < CacheSweeper::Base
  # Configure this sweeper's behavior
  sweeper_options trigger: :request, mode: :async, queue: :products

  # Clear cache when name or price changes
  watch attributes: [:name, :price], keys: ->(product) { ["product:#{product.id}"] }

  # Clear cache when product is created, updated, or destroyed
  watch attributes: [:name, :price], keys: ->(product) { ["products:index", "products:featured"] }
end
```

### 4. Start Sidekiq

```sh
bundle exec sidekiq
```

That's it! Your cache will now be automatically invalidated when products change.

## Configuration

### Global Configuration

Configure in `config/initializers/cache_sweeper.rb`:

```ruby
# Logging configuration
CacheSweeper.logger = Rails.logger
CacheSweeper.log_level = :info  # :debug, :info, :warn, :error

# Cache invalidation configuration (optional - has sensible defaults)
CacheSweeper.trigger = :request        # :instant or :request
CacheSweeper.mode = :async             # :async or :inline
CacheSweeper.queue = :low              # Sidekiq queue name
CacheSweeper.sidekiq_options = { retry: false }
CacheSweeper.delete_multi_batch_size = 100  # Batch size for efficient cache deletion
```

### Sweeper-Level Configuration

Use the `sweeper_options` DSL for clean sweeper configuration:

```ruby
class OrderSweeper < CacheSweeper::Base
  sweeper_options trigger: :request, mode: :async, queue: :orders
  # ... watch rules
end
```

### Rule-Level Configuration

Override configuration for specific rules:

```ruby
class MixedSweeper < CacheSweeper::Base
  # Instant deletion for critical data
  watch attributes: [:name], keys: ->(obj) { ["instant:#{obj.id}"] }, 
       trigger: :instant, mode: :inline
  
  # Async processing for less critical data
  watch attributes: [:description], keys: ->(obj) { ["async:#{obj.id}"] }, 
       trigger: :request, mode: :async, queue: :background
end
```

### Configuration Precedence

Configuration is resolved in this order (highest to lowest priority):

1. **Rule-level** - Options passed to individual `watch` calls
2. **Sweeper-level** - Configuration set on the sweeper class
3. **Global-level** - Default configuration set globally

### Configuration Options

- **`trigger`**: `:instant` (delete immediately) or `:request` (batch until end of request)
- **`mode`**: `:async` (use Sidekiq) or `:inline` (synchronous)
- **`queue`**: Sidekiq queue name (e.g., `:low`, `:high`, `:background`)
- **`sidekiq_options`**: Hash of Sidekiq options (e.g., `{ retry: false, backtrace: true }`)
- **`delete_multi_batch_size`**: Number of keys to delete in each batch (default: 100)

## Usage Examples

### Basic Sweeper

```ruby
# app/cache_sweepers/product_sweeper.rb
class ProductSweeper < CacheSweeper::Base
  watch attributes: [:name, :price], keys: ->(product) { ["product:#{product.id}"] }
end
```

### Association Sweeper

```ruby
# app/cache_sweepers/package_sweeper.rb
class PackageSweeper < CacheSweeper::Base
  # Clear cache when package name changes
  watch attributes: [:name], keys: ->(package) { ["package:#{package.id}"] }
  
  # Clear cache when associated products change
  watch :products, attributes: [:name], keys: ->(product) { 
    product.packages.map { |pkg| "package:#{pkg.id}" } 
  }
end
```

### Conditional Cache Invalidation

```ruby
# app/cache_sweepers/user_sweeper.rb
class UserSweeper < CacheSweeper::Base
  # Clear cache when user profile changes
  watch attributes: [:name, :email], keys: ->(user) { ["user:#{user.id}", "user:#{user.id}:profile"] }

  # Clear cache with custom condition
  watch attributes: [:last_login_at], keys: ->(user) { ["users:active"] },
       if: ->(user) { user.last_login_at_changed? && user.last_login_at > 1.day.ago }
end
```

### Mixed Configuration Sweeper

```ruby
# app/cache_sweepers/order_sweeper.rb
class OrderSweeper < CacheSweeper::Base
  # Default configuration for this sweeper
  sweeper_options trigger: :request, mode: :async, queue: :orders

  # Critical data - instant deletion
  watch attributes: [:status], keys: ->(order) { ["order:#{order.id}"] },
       trigger: :instant, mode: :inline

  # Less critical data - async processing
  watch attributes: [:notes], keys: ->(order) { ["order:#{order.id}:notes"] },
       trigger: :request, mode: :async, queue: :background

  # Association changes
  watch :order_items, attributes: [:quantity, :price], keys: ->(order_item) {
    ["order:#{order_item.order_id}", "order:#{order_item.order_id}:total"]
  }
end
```

### Custom Callback Events

```ruby
# app/cache_sweepers/notification_sweeper.rb
class NotificationSweeper < CacheSweeper::Base
  # Only clear cache on create and destroy, not update
  watch attributes: [:message], keys: ->(notification) { ["notifications:count"] },
       on: [:create, :destroy]
  
  # Use before_commit instead of after_commit
  watch attributes: [:read_at], keys: ->(notification) { ["user:#{notification.user_id}:unread_count"] },
       callback: :before_commit
end
```

## API Reference

### Sweeper DSL

#### `watch(association = nil, **options)`

Define cache invalidation rules.

**Parameters:**

- **`association`** (optional): Association name to watch (e.g., `:products`, `:order_items`)
- **`attributes`**: Array of attributes to watch for changes (e.g., `[:name, :price]`)
- **`keys`**: Proc or array of cache keys to invalidate
- **`if`**: Proc or method name for conditional invalidation
- **`trigger`**: `:instant` or `:request` (per rule)
- **`mode`**: `:async` or `:inline` (per rule)
- **`queue`**: Sidekiq queue name (per rule)
- **`sidekiq_options`**: Hash of Sidekiq options (per rule)
- **`callback`**: Callback type (`:after_commit`, `:before_commit`, etc.)
- **`on`**: Events to watch (`[:create, :update, :destroy]`)

**Examples:**

```ruby
# Basic usage
watch attributes: [:name], keys: ->(obj) { ["key:#{obj.id}"] }

# Association watching
watch :products, attributes: [:name], keys: ->(product) { ["product:#{product.id}"] }

# Conditional invalidation
watch attributes: [:status], keys: ->(obj) { ["key"] }, 
     if: ->(obj) { obj.status == 'published' }

# Custom events
watch attributes: [:name], keys: ->(obj) { ["key"] }, 
     on: [:create, :destroy]
```

#### `sweeper_options(**options)`

Configure sweeper-level behavior.

**Parameters:**

- **`trigger`**: `:instant` or `:request`
- **`mode`**: `:async` or `:inline`
- **`queue`**: Sidekiq queue name
- **`sidekiq_options`**: Hash of Sidekiq options

**Example:**

```ruby
class MySweeper < CacheSweeper::Base
  sweeper_options trigger: :request, mode: :async, queue: :low
end
```

### Global Configuration

#### `CacheSweeper.logger = logger`

Set the logger for cache actions.

#### `CacheSweeper.log_level = level`

Set minimum log level (`:debug`, `:info`, `:warn`, `:error`).

#### Global Configuration Attributes

Configure global cache invalidation behavior using direct attribute assignment:

**Example:**

```ruby
CacheSweeper.trigger = :request
CacheSweeper.mode = :async
CacheSweeper.queue = :low
CacheSweeper.sidekiq_options = { retry: false }
```

## Logging

The gem provides comprehensive logging to help debug cache invalidation issues.

### Log Levels

- **`:debug`** - All logging enabled (initialization, rule execution, performance, cache operations, async jobs, middleware)
- **`:info`** - Important events (initialization, cache operations, async jobs, middleware)
- **`:warn`** - Warnings and errors only
- **`:error`** - Errors only

### Default Log Levels

- **Development**: `:debug` (all logging enabled)
- **Production**: `:warn` (warnings and errors only)
- **Other environments**: `:info`

### Log Output

Log output includes:

- **Initialization**: Sweeper loading and model attachment
- **Rule execution**: Which rules are triggered, condition evaluation, cache key generation
- **Performance**: Timing for cache operations and rule execution
- **Cache operations**: Cache key invalidation details
- **Async jobs**: Job scheduling and execution status
- **Middleware**: Request-level batching and flushing
- **Errors**: Detailed error information with context and stack traces

### Example Log Output

```
[CacheSweeper] [2024-01-15 10:30:45.123] [INFO] Initialization: Processing sweeper: ProductSweeper
[CacheSweeper] [2024-01-15 10:30:45.124] [DEBUG] Rule execution: ProductSweeper -> Product#123
[CacheSweeper] [2024-01-15 10:30:45.125] [INFO] Cache operations: Deleted instantly: product:123
[CacheSweeper] [2024-01-15 10:30:45.126] [DEBUG] Performance: cache_invalidation took 2.456ms
```

### Debugging Configuration

```ruby
# Enable all logging for debugging
CacheSweeper.logger = Rails.logger
CacheSweeper.log_level = :debug  # Shows everything

# Or use different levels
CacheSweeper.log_level = :info   # Shows important events only
CacheSweeper.log_level = :warn   # Shows warnings and errors only
CacheSweeper.log_level = :error  # Shows errors only
```

## Middleware

The `CacheSweeperFlushMiddleware` handles request-level batching. It automatically flushes all pending cache keys at the end of each request.

### Setup

Add to `config/application.rb`:

```ruby
config.middleware.use CacheSweeperFlushMiddleware
```

### How It Works

1. When `trigger: :request` is used, cache keys are batched during the request
2. At the end of the request, the middleware flushes all pending keys
3. Keys are processed according to their `mode` setting (`:async` or `:inline`)

### Middleware Order

Place the middleware after other middleware that might affect caching:

```ruby
# config/application.rb
config.middleware.use SomeOtherMiddleware
config.middleware.use CacheSweeperFlushMiddleware
```

## Testing

### Basic Testing

You can test sweepers using standard Rails/ActiveRecord test frameworks:

```ruby
# test/sweepers/product_sweeper_test.rb
class ProductSweeperTest < ActiveSupport::TestCase
  test "clears cache when product name changes" do
    product = Product.create!(name: "Original Name")
    
    # Mock cache
    Rails.cache.expects(:delete).with("product:#{product.id}")
    
    product.update!(name: "New Name")
  end
end
```

### Testing Async Jobs

For async jobs, ensure Sidekiq is running or stub the worker:

```ruby
# test/sweepers/async_sweeper_test.rb
class AsyncSweeperTest < ActiveSupport::TestCase
  test "schedules async job for cache deletion" do
    # Stub Sidekiq worker
    CacheSweeper::AsyncWorker.expects(:perform_async).with(["key1", "key2"])
    
    # Trigger the change
    product = Product.create!(name: "Test Product")
  end
end
```

### Testing with Sidekiq

For integration tests with Sidekiq:

```ruby
# test/integration/cache_sweeper_integration_test.rb
class CacheSweeperIntegrationTest < ActionDispatch::IntegrationTest
  test "async cache deletion works end-to-end" do
    # Ensure Sidekiq is running
    Sidekiq::Testing.inline! do
      product = Product.create!(name: "Test Product")
      # Cache should be cleared synchronously
    end
  end
end
```

## Troubleshooting

### Common Issues

#### Sidekiq Not Running

**Problem**: Async cache deletion doesn't work.

**Solution**: Ensure Sidekiq is running:

```sh
bundle exec sidekiq
```

#### Sweepers Not Loading

**Problem**: Sweepers aren't being loaded or attached to models.

**Solution**: 
1. Ensure sweepers are in `app/cache_sweepers/` directory
2. Ensure sweepers inherit from `CacheSweeper::Base`
3. Check that the sweeper files are named `*_sweeper.rb`

#### Cache Keys Not Being Cleared

**Problem**: Cache keys aren't being invalidated when models change.

**Solution**:
1. Enable debug logging: `CacheSweeper.log_level = :debug`
2. Check that the correct attributes are being watched
3. Verify cache key generation logic
4. Ensure the model callbacks are being triggered

#### Middleware Not Flushing

**Problem**: Request-level batching isn't flushing at the end of requests.

**Solution**:
1. Ensure `CacheSweeperFlushMiddleware` is added to the middleware stack
2. Check middleware order in `config/application.rb`
3. Verify that `trigger: :request` is being used

### Debugging Steps

1. **Enable comprehensive logging**:
   ```ruby
   CacheSweeper.logger = Rails.logger
   CacheSweeper.log_level = :debug
   ```

2. **Check sweeper loading**:
   ```ruby
   # In Rails console
   CacheSweeper::Base.descendants
   ```

3. **Verify model callbacks**:
   ```ruby
   # In Rails console
   Product._commit_callbacks.map(&:filter)
   ```

4. **Test cache key generation**:
   ```ruby
   # In Rails console
   product = Product.first
   sweeper = ProductSweeper.new
   # Test your key generation logic
   ```

### Performance Considerations

- **Use `:instant` trigger** for critical cache that must be cleared immediately
- **Use `:request` trigger** for less critical cache to reduce database load
- **Use `:async` mode** for high-volume applications to avoid blocking requests
- **Use `:inline` mode** for low-volume applications or when immediate consistency is required
- **Monitor Sidekiq queue sizes** to ensure async jobs are being processed
- **Optimize batch sizes**: Adjust `delete_multi_batch_size` based on your cache store's performance
  - **Redis**: 100-500 keys per batch works well
  - **Memcached**: 50-200 keys per batch is optimal
  - **File store**: 10-50 keys per batch to avoid I/O bottlenecks

### Memory Usage

- Request-level batching stores cache keys in memory during the request
- For high-volume applications, consider using `:instant` trigger to avoid memory buildup
- Monitor RequestStore memory usage in production

## Contributing

1. Fork the repository
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create a new Pull Request

### Development Setup

1. Clone the repository
2. Run `bundle install`
3. Run tests with `bundle exec rspec`
4. Run linting with `bundle exec rubocop`

### Code Style

- Follow Ruby style guidelines
- Write tests for new features
- Update documentation for API changes
- Use meaningful commit messages

## License

MIT License. See [LICENSE.txt](LICENSE.txt) for details.

## Links

- [GitHub Repository](https://github.com/rafayqayyum/cache_sweeper)
- [MIT License](https://opensource.org/licenses/MIT)
- [RubyGems](https://rubygems.org/gems/cache_sweeper)
