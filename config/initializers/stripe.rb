require 'stripe'

# Configuration for webhook endpoints
Stripe.api_version = '2023-10-16'

# Set API key based on environment
if Rails.env.production?
  # Production uses Rails credentials
  Stripe.api_key = Rails.application.credentials.dig(:stripe, :secret_key)
else
  # Development/test uses ENV variables
  Stripe.api_key = ENV['STRIPE_SECRET_KEY']
end

# Verify configuration in non-production environments
unless Rails.env.production?
  if Stripe.api_key.present?
    Rails.logger.info "Stripe initialized with API version #{Stripe.api_version}"
    Rails.logger.info "Using #{Rails.env.development? ? 'test' : 'live'} mode"
  else
    Rails.logger.warn "Stripe not configured - set STRIPE_SECRET_KEY environment variable"
  end
end