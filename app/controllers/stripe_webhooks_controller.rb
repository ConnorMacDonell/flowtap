class StripeWebhooksController < ApplicationController
  # Skip CSRF verification for webhooks
  skip_before_action :verify_authenticity_token
  
  # No authentication needed - we verify with signature
  skip_before_action :authenticate_user!, if: -> { defined?(authenticate_user!) }

  def create
    payload = request.body.read
    sig_header = request.env['HTTP_STRIPE_SIGNATURE']
    endpoint_secret = ENV['STRIPE_WEBHOOK_SECRET']

    begin
      event = Stripe::Webhook.construct_event(payload, sig_header, endpoint_secret)
    rescue JSON::ParserError => e
      Rails.logger.error "Stripe webhook: Invalid payload: #{e.message}"
      render json: { error: 'Invalid payload' }, status: 400
      return
    rescue Stripe::SignatureVerificationError => e
      Rails.logger.error "Stripe webhook: Invalid signature: #{e.message}"
      render json: { error: 'Invalid signature' }, status: 400
      return
    end

    # Handle the event
    case event['type']
    when 'customer.created'
      handle_customer_created(event['data']['object'])
    when 'customer.updated'
      handle_customer_updated(event['data']['object'])
    when 'customer.deleted'
      handle_customer_deleted(event['data']['object'])
    when 'invoice.payment_succeeded'
      handle_payment_succeeded(event['data']['object'])
    when 'invoice.payment_failed'
      handle_payment_failed(event['data']['object'])
    when 'customer.subscription.created'
      handle_subscription_created(event['data']['object'])
    when 'customer.subscription.updated'
      handle_subscription_updated(event['data']['object'])
    when 'customer.subscription.deleted'
      handle_subscription_deleted(event['data']['object'])
    else
      Rails.logger.info "Stripe webhook: Unhandled event type: #{event['type']}"
    end

    render json: { received: true }, status: 200
  end

  private

  def handle_customer_created(customer)
    Rails.logger.info "Stripe webhook: Customer created #{customer['id']}"
    # Find user by email and update stripe_customer_id
    user = User.find_by(email: customer['email'])
    if user
      user.update!(stripe_customer_id: customer['id'])
    else
      Rails.logger.warn "Stripe webhook: No user found for customer #{customer['id']} with email #{customer['email']}"
    end
  end

  def handle_customer_updated(customer)
    Rails.logger.info "Stripe webhook: Customer updated #{customer['id']}"
    user = User.find_by(stripe_customer_id: customer['id'])
    if user
      # Update user email if changed in Stripe
      if user.email != customer['email']
        user.update!(email: customer['email'])
      end
    else
      Rails.logger.warn "Stripe webhook: No user found for customer #{customer['id']}"
    end
  end

  def handle_customer_deleted(customer)
    Rails.logger.info "Stripe webhook: Customer deleted #{customer['id']}"
    user = User.find_by(stripe_customer_id: customer['id'])
    if user
      user.update!(stripe_customer_id: nil)
    else
      Rails.logger.warn "Stripe webhook: No user found for customer #{customer['id']}"
    end
  end

  def handle_payment_succeeded(invoice)
    Rails.logger.info "Stripe webhook: Payment succeeded for invoice #{invoice['id']}"
    customer_id = invoice['customer']
    user = User.find_by(stripe_customer_id: customer_id)
    
    if user && user.subscription
      # Update subscription period
      subscription_id = invoice['subscription']
      if subscription_id
        stripe_subscription = Stripe::Subscription.retrieve(subscription_id)
        user.subscription.update!(
          current_period_start: Time.at(stripe_subscription.current_period_start),
          current_period_end: Time.at(stripe_subscription.current_period_end)
        )
      end
    else
      Rails.logger.warn "Stripe webhook: No user/subscription found for customer #{customer_id}"
    end
  end

  def handle_payment_failed(invoice)
    Rails.logger.warn "Stripe webhook: Payment failed for invoice #{invoice['id']}"
    customer_id = invoice['customer']
    user = User.find_by(stripe_customer_id: customer_id)
    
    if user
      # In the future, send payment failed email or take other action
      Rails.logger.info "Payment failed for user #{user.id} (#{user.email})"
    else
      Rails.logger.warn "Stripe webhook: No user found for customer #{customer_id}"
    end
  end

  def handle_subscription_created(subscription)
    Rails.logger.info "Stripe webhook: Subscription created #{subscription['id']}"
    customer_id = subscription['customer']
    user = User.find_by(stripe_customer_id: customer_id)
    
    if user && user.subscription
      # Map Stripe price ID to our tier
      tier = map_price_id_to_tier(subscription['items']['data'][0]['price']['id'])
      
      user.subscription.update!(
        status: tier,
        stripe_subscription_id: subscription['id'],
        current_period_start: Time.at(subscription['current_period_start']),
        current_period_end: Time.at(subscription['current_period_end'])
      )
    else
      Rails.logger.warn "Stripe webhook: No user/subscription found for customer #{customer_id}"
    end
  end

  def handle_subscription_updated(subscription)
    Rails.logger.info "Stripe webhook: Subscription updated #{subscription['id']}"
    user_subscription = Subscription.find_by(stripe_subscription_id: subscription['id'])
    
    if user_subscription
      tier = map_price_id_to_tier(subscription['items']['data'][0]['price']['id'])
      
      user_subscription.update!(
        status: tier,
        current_period_start: Time.at(subscription['current_period_start']),
        current_period_end: Time.at(subscription['current_period_end']),
        canceled_at: subscription['canceled_at'] ? Time.at(subscription['canceled_at']) : nil
      )
    else
      Rails.logger.warn "Stripe webhook: No subscription found with ID #{subscription['id']}"
    end
  end

  def handle_subscription_deleted(subscription)
    Rails.logger.info "Stripe webhook: Subscription deleted #{subscription['id']}"
    user_subscription = Subscription.find_by(stripe_subscription_id: subscription['id'])
    
    if user_subscription
      user_subscription.update!(
        status: 'free',  # Revert to free plan
        stripe_subscription_id: nil,
        canceled_at: Time.current,
        current_period_start: nil,
        current_period_end: nil
      )
    else
      Rails.logger.warn "Stripe webhook: No subscription found with ID #{subscription['id']}"
    end
  end

  def map_price_id_to_tier(price_id)
    # Map Stripe price IDs to our subscription tiers
    # These would be configured when setting up Stripe products
    case price_id
    when ENV['STRIPE_STANDARD_PRICE_ID']
      'standard'
    when ENV['STRIPE_PREMIUM_PRICE_ID']
      'premium'
    else
      'free'  # Default fallback
    end
  end
end