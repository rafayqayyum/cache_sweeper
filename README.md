# CacheSweeper

Declarative cache invalidation for ActiveRecord. Describe which model changes invalidate which cache keys in
dedicated sweeper classes, and CacheSweeper deletes them after the transaction commits: inline, batched per
request or job, or in the background through ActiveJob.

```ruby
class CatalogSweeper < CacheSweeper::Base
  watch Product, only: %i[name price slug] do |product|
    ["products/#{product.slug}", "products/#{product.slug_before_last_save}", "products/index"]
  end

  watch Variant, only: :price, on: :update do |variant|
    product_keys(variant.product)
  end

  watch Review, on: %i[create destroy], if: :published? do |review|
    product_keys(review.product)
  end

  private

  def product_keys(product)
    ["products/#{product.slug}", [product, :card]]
  end
end
```

## Requirements

- Ruby 3.3+
- Rails 7.1+ (ActiveRecord, ActiveJob, ActiveSupport)

## Installation

```ruby
gem "cache_sweeper"
```

Put sweepers in `app/sweepers`. They are loaded at boot and reloaded with the rest of your code in development.

## Watching models

```ruby
watch Model, on: %i[create update destroy], only: nil, if: nil, unless: nil, delivery: nil, queue: nil do |record|
  # return one cache key or an array of keys
end
```

| Option     | Meaning                                                                                       |
|------------|-----------------------------------------------------------------------------------------------|
| `on`       | Events that trigger the sweep. Defaults to all three.                                         |
| `only`     | Attributes whose change triggers an `update` sweep. Creates and destroys always sweep.        |
| `if`       | Symbol (method on the record) or Proc (receives the record, runs on the sweeper) to require. |
| `unless`   | Same as `if`, inverted.                                                                       |
| `delivery` | Overrides the sweeper's delivery for this rule.                                               |
| `queue`    | ActiveJob queue for `:async` delivery.                                                        |

A sweeper can watch any number of models, and any number of sweepers can watch the same model, so group them by
what they cache rather than by model. The block and Proc conditions run on a sweeper instance, so private helper
methods are available to them. Sweeps run in `after_commit`, so rolled-back changes never invalidate anything.

### Keys

The block returns a single key or an array of keys. Keys are expanded exactly like `Rails.cache` expands them,
so anything you can pass to `Rails.cache.fetch` works, including records and composite keys. Nest composite keys
inside the returned array:

```ruby
watch Product do |product|
  ["products/index", [product, :card], { locale: I18n.locale, page: :home }]
end
```

`nil` and blank keys are dropped and duplicates removed. Use Rails' `*_before_last_save` readers to sweep keys
built from a previous value, such as an old slug.

## Delivery

| Mode       | When keys are deleted                                                                              |
|------------|----------------------------------------------------------------------------------------------------|
| `:inline`  | Immediately after commit. Default.                                                                 |
| `:batched` | At the end of the current request or job, deduplicated into one `delete_multi`.                    |
| `:async`   | At the end of the current request or job, enqueued as `CacheSweeper::DeleteJob`s.                  |

`:inline` is the default because it is the only mode where code running after the commit, including the rest of
the same request, never reads a stale entry. `:batched` and `:async` trade that for fewer cache round trips: for
a request, the keys are deleted after the response has been sent, so a write followed by a cached read in the
same request, or a request arriving in that gap, sees the old value. Opt into them per sweeper or per rule where
that is acceptable.

Batching hooks into the Rails executor, which wraps web requests, ActiveJob and Sidekiq jobs, and ActionCable.
Pending keys are flushed even when the request raises, and early once `max_pending_keys` are waiting, so a
long job updating many records deletes as it goes instead of holding every key until it ends. Async keys are
split into jobs of `batch_size` keys and enqueued in bulk.

`rails runner` wraps the whole script in the executor, so a runner script is one unit of work: its keys are
deleted when it finishes, or every `max_pending_keys` keys. Outside an executor (console, rake tasks) `:batched`
deletes and `:async` enqueues straight away. To batch a console session or rake task, wrap it:

```ruby
Rails.application.executor.wrap do
  Product.find_each { |product| product.update!(price: product.price * 1.1) }
end
```

Set the delivery per sweeper or per rule:

```ruby
class SearchSweeper < CacheSweeper::Base
  delivery :async, queue: :low

  watch Product, only: :name do |product|
    "search/#{product.category_id}"
  end

  watch Product, only: :price, delivery: :inline do |product|
    "prices/#{product.id}"
  end
end
```

Rule options win over sweeper options, which win over the global configuration.

## Configuration

```ruby
# config/initializers/cache_sweeper.rb
CacheSweeper.configure do |config|
  config.cache_store = Rails.cache       # any ActiveSupport::Cache::Store, defaults to Rails.cache
  config.delivery = :inline              # :inline, :batched or :async
  config.queue = :default                # ActiveJob queue for :async
  config.batch_size = 100                # keys per delete_multi call and per DeleteJob
  config.max_pending_keys = 1_000        # flush a request's or job's batch early at this size
  config.raise_errors = Rails.env.local? # raise sweep errors instead of reporting them
  config.force_inline = false            # delete inline regardless of declared delivery
  config.sweeper_paths = ["app/sweepers"]
end
```

## Deleting manually

```ruby
CacheSweeper.delete("products/index", [product, :card])
```

## Errors

A failing key block or cache delete never breaks the request that committed the change. Errors go to
`Rails.error` (`ActiveSupport.error_reporter`) with `source: "cache_sweeper"` and are logged. With `raise_errors`
enabled, the default in development and test, they are raised instead. `DeleteJob` always raises so your queue
adapter can retry it.

## Instrumentation

| Event                     | Payload                                          |
|---------------------------|--------------------------------------------------|
| `sweep.cache_sweeper`     | `sweeper`, `record`, `event`, `keys`, `delivery` |
| `delete.cache_sweeper`    | `keys`                                           |
| `failure.cache_sweeper`   | `error` and context                              |

Sweeps and deletes are logged at debug level and failures at error level.

## Testing

Requests and jobs in your test suite run inside the executor, so sweepers using `:batched` or `:async` only
sweep when the test's unit of work finishes. Force inline deletion in tests that assert on the cache:

```ruby
# config/environments/test.rb
config.after_initialize { CacheSweeper.config.force_inline = true }
```

## Limitations

Sweeps rely on `after_commit`, so bulk operations that skip callbacks (`update_all`, `delete_all`, `insert_all`,
`upsert_all`) don't sweep. `only:` reads `saved_changes`, which reflects the record's last save within the
transaction.

## Development

```sh
bundle install
bundle exec rake                    # rubocop, both suites, 100% line and branch coverage
bundle exec rspec spec/unit         # ActiveRecord without Rails
bundle exec rspec spec/rails        # Railtie, executor and reloading against a dummy app
RAILS_VERSION=7.2 bundle update && bundle exec rake spec
```

The two suites run in separate processes so the unit suite proves the gem works without Rails loaded. Their
coverage is merged before the threshold is enforced. The store specs run against Redis and Memcached when they
are reachable on their default ports, and CI always runs them.

CI also runs RuboCop, `bundle-audit` and a strict `gem build`; CodeQL scans the code weekly and on every PR.

### Releasing

Bump `CacheSweeper::VERSION`, update the CHANGELOG, then tag and push. The Release workflow runs the suite and
publishes to RubyGems through trusted publishing:

```sh
git tag v1.0.0 && git push origin v1.0.0
```

## License

MIT. See [LICENSE.txt](LICENSE.txt).
