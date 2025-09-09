require 'capybara/rails'
require 'capybara/rspec'

RSpec.configure do |config|
  config.before(:each, type: :feature) do
    # Reset Capybara session before each test
    Capybara.reset_sessions!
  end
end