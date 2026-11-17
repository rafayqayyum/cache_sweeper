# frozen_string_literal: true

require "simplecov"
SimpleCov.command_name "rails"
SimpleCov.coverage_dir "coverage/rails"
SimpleCov.start "cache_sweeper"

DUMMY_DATABASE = File.expand_path("../tmp/dummy.sqlite3", __dir__)
ENV["RAILS_ENV"] = "test"
ENV["DATABASE_URL"] = "sqlite3:#{DUMMY_DATABASE}"

require "rails"
require "active_record/railtie"
require "active_job/railtie"
require "cache_sweeper"

module Dummy
  class Application < Rails::Application
    config.root = File.expand_path("dummy", __dir__)
    config.load_defaults "#{Rails::VERSION::MAJOR}.#{Rails::VERSION::MINOR}"
    config.eager_load = false
    config.enable_reloading = true
    config.cache_store = :memory_store
    config.active_job.queue_adapter = :test
    config.logger = ActiveSupport::Logger.new(nil)
    config.secret_key_base = "dummy"
  end
end

FileUtils.mkdir_p(File.dirname(DUMMY_DATABASE))
FileUtils.rm_f(DUMMY_DATABASE)
CacheSweeper.config.sweeper_paths = ["app/sweepers", "app/missing"]
Rails.application.initialize!

ActiveRecord::Migration.verbose = false
ActiveRecord::Schema.define do
  create_table :articles do |t|
    t.string :title
    t.text :body
    t.timestamps
  end
end

require_relative "support/rspec"

RSpec.configure do |config|
  config.before do
    Rails.cache.clear
    enqueued_jobs.clear
  end

  config.after { Article.delete_all }
end
