# frozen_string_literal: true

SimpleCov.profiles.define "cache_sweeper" do
  enable_coverage :branch
  cover "lib/**/*.rb"
  # Bundler loads it through the gemspec before coverage starts.
  skip "lib/cache_sweeper/version.rb"
end
