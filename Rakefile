require "bundler/gem_tasks"
require "rspec/core/rake_task"

RSpec::Core::RakeTask.new(:spec)

if defined?(Rake)
  load File.expand_path("lib/tasks/cache_sweeper.rake", __dir__)
  Dir.glob('lib/tasks/**/*.rake').each { |r| load r }
end
