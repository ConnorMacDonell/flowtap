# frozen_string_literal: true

class Rack::Attack
  # Use Redis for rate limit storage
  Rack::Attack.cache.store = ActiveSupport::Cache::RedisCacheStore.new(
    url: ENV['REDIS_URL'] || 'redis://localhost:6379/1'
  )

  # Limit login attempts by IP (5 attempts per minute)
  throttle('logins/ip', limit: 5, period: 1.minute) do |req|
    if req.path == '/users/sign_in' && req.post?
      req.ip
    end
  end

  # Limit password reset requests by IP
  throttle('password_reset/ip', limit: 3, period: 10.minutes) do |req|
    if req.path == '/users/password' && req.post?
      req.ip
    end
  end

  # General request limit per IP
  throttle('req/ip', limit: 300, period: 5.minutes) do |req|
    req.ip unless req.path.start_with?('/assets')
  end
end
