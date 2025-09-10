require 'stripe'

# Configuration for webhook endpoints
Stripe.api_version = '2023-10-16'

# Use ENV variables for all environments for consistency
Stripe.api_key = ENV['STRIPE_SECRET_KEY']

# Verify configuration
if Stripe.api_key.present?
  Rails.logger.info "Stripe initialized with API version #{Stripe.api_version}"
  Rails.logger.info "Using #{Rails.env.development? ? 'test' : 'live'} mode"
else
  Rails.logger.warn "Stripe not configured - set STRIPE_SECRET_KEY environment variable"
end