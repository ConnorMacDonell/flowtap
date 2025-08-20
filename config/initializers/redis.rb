# Redis configuration for development and production
Rails.application.configure do
  config.cache_store = :redis_cache_store, {
    url: ENV.fetch("REDIS_URL", "redis://localhost:6379/0"),
    reconnect_attempts: 1,
    reconnect_delay: 0,
    reconnect_delay_max: 0.5,
    error_handler: -> (method:, returning:, exception:) {
      Rails.logger.error "Redis error: #{exception.message}"
    }
  }
end

# Configure Redis connection for Sidekiq
redis_config = { url: ENV.fetch("REDIS_URL", "redis://localhost:6379/0") }

# Add SSL configuration for Heroku Redis
if ENV['REDIS_URL']&.start_with?('rediss://')
  redis_config[:ssl_params] = { verify_mode: OpenSSL::SSL::VERIFY_NONE }
end

Sidekiq.configure_server do |config|
  config.redis = redis_config
end

Sidekiq.configure_client do |config|
  config.redis = redis_config
end