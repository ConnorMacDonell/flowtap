class StripeSubscriptionService
  attr_reader :user

  def initialize(user)
    @user = user
  end

  # Creates a Stripe Checkout Session for the user's subscription
  # Returns the checkout URL on success, nil on failure
  def create_checkout_session(success_url:, cancel_url:)
    ensure_stripe_customer!
    ensure_subscription_record!

    begin
      session = Stripe::Checkout::Session.create(
        customer: user.stripe_customer_id,
        line_items: [{
          price: ENV['STRIPE_STANDARD_PRICE_ID'],
          quantity: 1
        }],
        mode: 'subscription',
        success_url: success_url,
        cancel_url: cancel_url,
        metadata: {
          user_id: user.id
        }
      )

      Rails.logger.info "StripeSubscriptionService: Created checkout session for user #{user.id}"
      session.url
    rescue Stripe::StripeError => e
      Rails.logger.error "StripeSubscriptionService: Failed to create checkout session for user #{user.id}: #{e.message}"
      nil
    end
  end

  # Cancels the user's Stripe subscription immediately
  # Returns true on success, false on failure
  # Raises error if cancellation is critical (e.g., during user deletion)
  def cancel_subscription(immediate: true)
    return true unless user.subscription&.stripe_subscription_id.present?

    begin
      # Cancel the subscription in Stripe
      Stripe::Subscription.cancel(user.subscription.stripe_subscription_id)

      # Update local subscription status immediately
      user.subscription.update!(
        status: 'canceled',
        canceled_at: Time.current,
        stripe_subscription_id: nil,
        current_period_start: nil,
        current_period_end: nil
      )

      Rails.logger.info "StripeSubscriptionService: Successfully canceled subscription #{user.subscription.stripe_subscription_id} for user #{user.id}"
      true
    rescue Stripe::StripeError => e
      Rails.logger.error "StripeSubscriptionService: Failed to cancel subscription for user #{user.id}: #{e.message}"

      # If this is a critical cancellation (immediate: true), raise the error
      # Otherwise return false and let the caller handle it
      raise e if immediate
      false
    end
  end

  # Cancels subscription at period end (allows user to use until billing cycle ends)
  # Returns true on success, false on failure
  def cancel_at_period_end
    return true unless user.subscription&.stripe_subscription_id.present?

    begin
      Stripe::Subscription.update(
        user.subscription.stripe_subscription_id,
        cancel_at_period_end: true
      )

      user.subscription.update!(
        canceled_at: Time.current
      )

      Rails.logger.info "StripeSubscriptionService: Set subscription #{user.subscription.stripe_subscription_id} to cancel at period end for user #{user.id}"
      true
    rescue Stripe::StripeError => e
      Rails.logger.error "StripeSubscriptionService: Failed to cancel subscription at period end for user #{user.id}: #{e.message}"
      false
    end
  end

  # Reactivates a subscription that was set to cancel at period end
  # Returns true on success, false on failure
  def reactivate_subscription
    return false unless user.subscription&.stripe_subscription_id.present?

    begin
      Stripe::Subscription.update(
        user.subscription.stripe_subscription_id,
        cancel_at_period_end: false
      )

      user.subscription.update!(
        canceled_at: nil
      )

      Rails.logger.info "StripeSubscriptionService: Reactivated subscription #{user.subscription.stripe_subscription_id} for user #{user.id}"
      true
    rescue Stripe::StripeError => e
      Rails.logger.error "StripeSubscriptionService: Failed to reactivate subscription for user #{user.id}: #{e.message}"
      false
    end
  end

  private

  # Ensures the user has a Stripe customer ID
  # Creates a new Stripe customer if one doesn't exist
  def ensure_stripe_customer!
    return if user.stripe_customer_id.present?

    begin
      customer = Stripe::Customer.create(
        email: user.email,
        name: user.full_name,
        metadata: {
          user_id: user.id
        }
      )
      user.update!(stripe_customer_id: customer.id)
      Rails.logger.info "StripeSubscriptionService: Created Stripe customer #{customer.id} for user #{user.id}"
    rescue Stripe::StripeError => e
      Rails.logger.error "StripeSubscriptionService: Failed to create Stripe customer for user #{user.id}: #{e.message}"
      raise
    end
  end

  # Ensures the user has a local subscription record
  # Creates an inactive subscription if one doesn't exist
  def ensure_subscription_record!
    return if user.subscription.present?
    user.create_subscription!(status: 'inactive')
    Rails.logger.info "StripeSubscriptionService: Created local subscription record for user #{user.id}"
  end
end
