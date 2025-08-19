class StripeWebhookJob < ApplicationJob
  queue_as :critical
  
  retry_on StandardError, wait: :polynomially_longer, attempts: 5
  
  def perform(event_data)
    Rails.logger.info "Processing Stripe webhook event"
    
    begin
      event = JSON.parse(event_data, symbolize_names: true)
      event_type = event[:type]
      event_id = event[:id]
      
      Rails.logger.info "Processing Stripe event: #{event_type} (#{event_id})"
      
      case event_type
      when 'customer.subscription.created'
        handle_subscription_created(event[:data][:object])
      when 'customer.subscription.updated'
        handle_subscription_updated(event[:data][:object])
      when 'customer.subscription.deleted'
        handle_subscription_deleted(event[:data][:object])
      when 'invoice.payment_succeeded'
        handle_payment_succeeded(event[:data][:object])
      when 'invoice.payment_failed'
        handle_payment_failed(event[:data][:object])
      when 'customer.created'
        handle_customer_created(event[:data][:object])
      when 'customer.updated'
        handle_customer_updated(event[:data][:object])
      else
        Rails.logger.info "Unhandled Stripe webhook event: #{event_type}"
      end
      
      Rails.logger.info "Successfully processed Stripe event: #{event_type} (#{event_id})"
      
    rescue JSON::ParserError => e
      Rails.logger.error "Invalid JSON in Stripe webhook: #{e.message}"
      raise
    rescue StandardError => e
      Rails.logger.error "StripeWebhookJob failed for event type #{event&.dig(:type) || 'unknown'}: #{e.message}"
      Rails.logger.error "Event data: #{event_data}"
      Rails.logger.error "Backtrace: #{e.backtrace.first(5).join('\n')}"
      raise
    end
  end
  
  private
  
  def handle_subscription_created(subscription)
    customer_id = subscription[:customer]
    user = User.find_by(stripe_customer_id: customer_id)
    return unless user
    
    tier = price_id_to_tier(subscription[:items][:data].first[:price][:id])
    old_tier = user.subscription.status
    
    user.subscription.update!(
      status: tier,
      stripe_subscription_id: subscription[:id],
      current_period_start: Time.at(subscription[:current_period_start]),
      current_period_end: Time.at(subscription[:current_period_end])
    )
    
    EmailJob.perform_later('UserMailer', 'subscription_updated', user.id, old_tier, tier)
  end
  
  def handle_subscription_updated(subscription)
    user_subscription = Subscription.find_by(stripe_subscription_id: subscription[:id])
    return unless user_subscription
    
    tier = price_id_to_tier(subscription[:items][:data].first[:price][:id])
    old_tier = user_subscription.status
    
    user_subscription.update!(
      status: tier,
      current_period_start: Time.at(subscription[:current_period_start]),
      current_period_end: Time.at(subscription[:current_period_end])
    )
    
    if old_tier != tier
      EmailJob.perform_later('UserMailer', 'subscription_updated', user_subscription.user.id, old_tier, tier)
    end
  end
  
  def handle_subscription_deleted(subscription)
    user_subscription = Subscription.find_by(stripe_subscription_id: subscription[:id])
    return unless user_subscription
    
    old_tier = user_subscription.status
    
    user_subscription.update!(
      status: 'free',
      stripe_subscription_id: nil,
      current_period_start: nil,
      current_period_end: nil,
      canceled_at: Time.current
    )
    
    EmailJob.perform_later('UserMailer', 'subscription_updated', user_subscription.user.id, old_tier, 'free')
  end
  
  def handle_payment_succeeded(invoice)
    # Log successful payment
    Rails.logger.info "Payment succeeded for invoice: #{invoice[:id]}"
  end
  
  def handle_payment_failed(invoice)
    customer_id = invoice[:customer]
    user = User.find_by(stripe_customer_id: customer_id)
    return unless user
    
    invoice_url = invoice[:hosted_invoice_url]
    EmailJob.perform_later('UserMailer', 'payment_failed', user.id, invoice_url)
  end
  
  def handle_customer_created(customer)
    Rails.logger.info "Customer created in Stripe: #{customer[:id]}"
    # Customer is already linked to user during subscription creation
    # No additional action needed
  end
  
  def handle_customer_updated(customer)
    user = User.find_by(stripe_customer_id: customer[:id])
    return unless user
    
    Rails.logger.info "Customer updated in Stripe for user: #{user.id}"
    
    # Update user information if Stripe customer data changed
    if customer[:email] && customer[:email] != user.email
      Rails.logger.info "Customer email mismatch - Stripe: #{customer[:email]}, User: #{user.email}"
    end
  end
  
  def price_id_to_tier(price_id)
    case price_id
    when ENV['STRIPE_STANDARD_PRICE_ID']
      'standard'
    when ENV['STRIPE_PREMIUM_PRICE_ID']
      'premium'
    else
      'free'
    end
  end
end