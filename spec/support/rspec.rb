# frozen_string_literal: true

require_relative "helpers"

RSpec.configure do |config|
  config.disable_monkey_patching!
  config.example_status_persistence_file_path = ".rspec_status"
  config.order = :random
  Kernel.srand config.seed

  config.mock_with(:rspec) { |mocks| mocks.verify_partial_doubles = true }
  config.include Helpers
end
