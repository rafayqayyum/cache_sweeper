# frozen_string_literal: true

require_relative "lib/cache_sweeper/version"

Gem::Specification.new do |spec|
  spec.name = "cache_sweeper"
  spec.version = CacheSweeper::VERSION
  spec.authors = ["Rafay Qayyum"]
  spec.email = ["rafayqayyum786@gmail.com"]

  spec.summary = "Declarative, rule-based cache invalidation for ActiveRecord models."
  spec.description = "Define which model changes invalidate which cache keys in dedicated sweeper classes. " \
                     "Deletes inline, batched per request or job, or asynchronously through ActiveJob."
  spec.homepage = "https://github.com/rafayqayyum/cache_sweeper"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.3"

  spec.metadata = {
    "source_code_uri" => spec.homepage,
    "changelog_uri" => "#{spec.homepage}/blob/main/CHANGELOG.md",
    "bug_tracker_uri" => "#{spec.homepage}/issues",
    "rubygems_mfa_required" => "true"
  }

  spec.files = Dir["lib/**/*.rb", "README.md", "CHANGELOG.md", "LICENSE.txt"]
  spec.require_paths = ["lib"]

  spec.add_dependency "activejob", ">= 7.1", "< 9"
  spec.add_dependency "activerecord", ">= 7.1", "< 9"
  spec.add_dependency "activesupport", ">= 7.1", "< 9"
  spec.add_dependency "zeitwerk", "~> 2.6"
end
