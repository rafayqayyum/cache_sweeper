require_relative 'lib/cache_sweeper/version'

Gem::Specification.new do |spec|
  spec.name          = "cache_sweeper"
  spec.version       = "0.1.0"
  spec.authors       = ["Rafay Qayyum"]
  spec.email         = ["rafayqayyum786@gmail.com"]

  spec.summary       = "Flexible, rule-based cache invalidation for Rails with batching, async jobs, and association support."
  spec.description   = "CacheSweeper is a highly configurable gem for Rails that enables rule-based cache invalidation, request-level batching, async Sidekiq jobs, association-aware sweeping, and more."
  spec.homepage      = "https://github.com/rafayqayyum/cache_sweeper"
  spec.license       = "MIT"
  spec.required_ruby_version = ">= 2.6.0"

  spec.files         = Dir.chdir(File.expand_path('..', __FILE__)) do
    `git ls-files -z`.split("\x0").reject { |f| f.match(%r{^(test|spec|features)/}) || f =~ /^\.rspec$/ || f =~ /^\.travis.yml$/ || f =~ /^bin\// }
  end
  spec.bindir        = "exe"
  spec.executables   = []
  spec.require_paths = ["lib"]

  spec.add_dependency "sidekiq", "~> 6.0"
  spec.add_dependency "request_store", "~> 1.7"
  spec.add_dependency "rails", ">= 6.0", "< 8.0"
end
