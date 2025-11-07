class StripeCheckoutService
  attr_reader :user, :success_url, :cancel_url

  def initialize(user, success_url:, cancel_url:)
    @user = user
    @success_url = success_url
    @cancel_url = cancel_url
  end

  # Creates a Stripe Checkout Session for the user's subscription
  # Returns the checkout URL on success, nil on failure
  def create_checkout_session
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

      session.url
    rescue Stripe::StripeError => e
      Rails.logger.error "StripeCheckoutService: Failed to create Checkout Session for user #{user.id}: #{e.message}"
      nil
    end
  end

  private

  def ensure_stripe_customer!
    return if user.stripe_customer_id.present?

    begin
      customer = Stripe::Customer.create(
        email: user.email,
        name: "#{user.first_name} #{user.last_name}".strip,
        metadata: {
          user_id: user.id
        }
      )
      user.update!(stripe_customer_id: customer.id)
    rescue Stripe::StripeError => e
      Rails.logger.error "StripeCheckoutService: Failed to create Stripe customer for user #{user.id}: #{e.message}"
      raise
    end
  end

  def ensure_subscription_record!
    return if user.subscription.present?
    user.create_subscription!(status: 'inactive')
  end
end
