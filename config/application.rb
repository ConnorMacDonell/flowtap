require_relative "boot"

require "rails/all"

# Require the gems listed in Gemfile, including any gems
# you've limited to :test, :development, or :production.
Bundler.require(*Rails.groups)

module SaasTemplate
  class Application < Rails::Application
    # Initialize configuration defaults for originally generated Rails version.
    config.load_defaults 7.1

    # Please, add to the `ignore` list any other `lib` subdirectories that do
    # not contain `.rb` files, or that should not be reloaded or eager loaded.
    # Common ones are `templates`, `generators`, or `middleware`, for example.
    config.autoload_lib(ignore: %w(assets tasks))

    # Configuration for the application, engines, and railties goes here.
    #
    # These settings can be overridden in specific environments using the files
    # in config/environments, which are processed later.
    #
    # config.time_zone = "Central Time (US & Canada)"
    # config.eager_load_paths << Rails.root.join("extras")
    
    # Configure Active Job to use Sidekiq
    config.active_job.queue_adapter = :sidekiq
    
    # Configure custom error handling
    config.exceptions_app = self.routes
    
    # Configure structured logging
    config.log_level = :info
    config.log_tags = [:request_id, :subdomain]
    
    # Add custom error pages
    config.consider_all_requests_local = false if Rails.env.production?
    
    # Configure timezone
    config.time_zone = 'UTC'

    # Enable Rack::Attack middleware for rate limiting
    config.middleware.use Rack::Attack

    # Error classes are now in app/models for better autoloading
  end
end
