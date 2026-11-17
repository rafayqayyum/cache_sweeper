# frozen_string_literal: true

source "https://rubygems.org"

gemspec

rails_version = ENV.fetch("RAILS_VERSION", "8.1")

gem "activejob", "~> #{rails_version}.0"
gem "activerecord", "~> #{rails_version}.0"
gem "railties", "~> #{rails_version}.0"
gem "sqlite3", rails_version == "7.1" ? "~> 1.4" : ">= 2.1"

gem "connection_pool", "< 3" if rails_version.start_with?("7.")
gem "dalli", "~> 3.2"
gem "redis", "~> 5.0"

gem "bundler-audit", require: false
gem "rake", "~> 13.0"
gem "rspec", "~> 3.13"
gem "rubocop", "~> 1.70", require: false
gem "rubocop-rake", require: false
gem "rubocop-rspec", require: false
gem "simplecov", "~> 1.3", require: false
