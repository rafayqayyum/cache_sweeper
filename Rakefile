# frozen_string_literal: true

require "bundler/gem_tasks"
require "rspec/core/rake_task"
require "rubocop/rake_task"

RuboCop::RakeTask.new

namespace :spec do
  desc "Remove previous coverage results"
  task :clean do
    rm_rf "coverage"
  end

  %w[unit rails].each do |suite|
    desc "Run the #{suite} suite"
    RSpec::Core::RakeTask.new(suite) { |task| task.pattern = "spec/#{suite}/**/*_spec.rb" }
  end

  desc "Merge both suites' coverage and enforce 100% line and branch coverage"
  task :coverage do
    require "simplecov"
    SimpleCov.collate Dir["coverage/{unit,rails}/.resultset.json"], "cache_sweeper" do
      coverage :line, minimum: 100
      coverage :branch, minimum: 100
    end
  end
end

desc "Run the unit and Rails suites with merged coverage"
task spec: %w[spec:clean spec:unit spec:rails spec:coverage]

task default: %i[rubocop spec]
