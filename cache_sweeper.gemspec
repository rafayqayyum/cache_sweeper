require_relative 'lib/cache_sweeper/version'

Gem::Specification.new do |spec|
  spec.name          = "cache_sweeper"
  spec.version       = CacheSweeper::VERSION
  spec.author        = "Rafay Qayyum"
  spec.email         = "rafayqayyum786@gmail.com"

  spec.summary       = "Flexible, rule-based cache invalidation for Rails with batching, async jobs, and association support."
  spec.homepage      = "https://github.com/rafayqayyum/cache_sweeper"
  spec.license       = "MIT"
  spec.required_ruby_version = ">= 2.6.0"

  spec.files         = Dir["*.{md,txt}", "{lib}/**/*"]
  spec.require_paths = ["lib"]

  spec.add_dependency "request_store", "~> 1.7"
  spec.add_dependency "rails", ">= 6.0", "< 8.0"
  spec.add_development_dependency "sidekiq", "~> 6.0"
end
