class SubscriptionsController < ApplicationController
  before_action :authenticate_user!

  def index
    @current_subscription = current_user.subscription
    @tiers = Subscription::TIERS
  end

  def show
    @subscription = current_user.subscription
  end

  def new
    @subscription = current_user.subscription
    
    # Check if user already has active subscription
    if @subscription&.active?
      redirect_to subscriptions_path, notice: 'You already have an active subscription'
      return
    end
    
    # Create subscription if it doesn't exist or is canceled
    unless @subscription
      @subscription = current_user.create_subscription!(status: 'inactive')
    end
  end

  def create
    @subscription = current_user.subscription

    # Check if user already has active subscription
    if @subscription&.active?
      redirect_to subscriptions_path, alert: 'You already have an active subscription'
      return
    end
    
    # Create subscription if it doesn't exist
    unless @subscription
      @subscription = current_user.create_subscription!(status: 'inactive')
    end

    # Create or update Stripe customer
    ensure_stripe_customer!

    # Redirect to Stripe payment link
    payment_link_url = ENV['STRIPE_PAYMENT_LINK']
    if payment_link_url.present?
      redirect_to payment_link_url, allow_other_host: true
    else
      redirect_to subscriptions_path, alert: 'Payment system unavailable. Please try again later.'
    end
  end

  def success
    if current_user.has_active_subscription?
      flash[:success] = "Welcome! Your subscription is now active."
    else
      flash[:notice] = "Payment successful! Your subscription is being activated."
    end
    redirect_to dashboard_path
  end

  def cancel_payment
    @message = 'Payment was cancelled. You can try again anytime.'
  end

  def cancel
    @subscription = current_user.subscription
    
    unless @subscription&.active?
      redirect_to subscriptions_path, alert: 'No active subscription to cancel'
      return
    end

    # Cancel the Stripe subscription
    if @subscription.stripe_subscription_id.present?
      begin
        Stripe::Subscription.cancel(@subscription.stripe_subscription_id)
        redirect_to subscriptions_path, notice: 'Subscription cancelled successfully!'
      rescue Stripe::StripeError => e
        redirect_to subscriptions_path, alert: "Error cancelling subscription: #{e.message}"
      end
    else
      redirect_to subscriptions_path, alert: 'No active subscription to cancel'
    end
  end

  private

  def ensure_stripe_customer!
    return if current_user.stripe_customer_id.present?

    begin
      customer = Stripe::Customer.create(
        email: current_user.email,
        name: "#{current_user.first_name} #{current_user.last_name}".strip,
        metadata: {
          user_id: current_user.id
        }
      )
      current_user.update!(stripe_customer_id: customer.id)
    rescue Stripe::StripeError => e
      Rails.logger.error "Failed to create Stripe customer: #{e.message}"
      raise
    end
  end


end