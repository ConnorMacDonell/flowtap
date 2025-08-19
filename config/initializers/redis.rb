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
Sidekiq.configure_server do |config|
  config.redis = { url: ENV.fetch("REDIS_URL", "redis://localhost:6379/0") }
end

Sidekiq.configure_client do |config|
  config.redis = { url: ENV.fetch("REDIS_URL", "redis://localhost:6379/0") }
end