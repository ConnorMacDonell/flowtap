class SubscriptionsController < ApplicationController
  before_action :authenticate_user!
  skip_before_action :check_subscription_status, only: [:index, :show, :new, :create, :success, :cancel_payment]

  def index
    @current_subscription = current_user.subscription
    @tiers = Subscription::TIERS
  end

  def show
    @subscription = current_user.subscription
  end

  def new
    # Check if user already has active subscription
    if current_user.has_active_subscription?
      redirect_to subscriptions_path, notice: 'You already have an active subscription'
      return
    end

    # Render subscription landing page - user will click button to proceed to Stripe
    @subscription_tier = Subscription::TIERS['paid']
  end

  def create
    # Check if user already has active subscription
    if current_user.has_active_subscription?
      redirect_to subscriptions_path, alert: 'You already have an active subscription'
      return
    end

    # Create Checkout Session using subscription service
    subscription_service = StripeSubscriptionService.new(current_user)
    checkout_url = subscription_service.create_checkout_session(
      success_url: success_subscriptions_url,
      cancel_url: cancel_payment_subscriptions_url
    )

    if checkout_url
      redirect_to checkout_url, allow_other_host: true
    else
      redirect_to subscriptions_path, alert: 'Payment system unavailable. Please try again later.'
    end
  end

  def success
    # Reload user to get latest subscription status in case webhook already processed
    current_user.reload

    if current_user.has_active_subscription?
      flash[:success] = "Welcome! Your subscription is now active."
      redirect_to dashboard_path
    else
      # Payment successful but webhook hasn't processed yet
      # Show a waiting page instead of redirecting immediately
      flash.now[:notice] = "Payment successful! Activating your subscription..."
      render :success
    end
  end

  def cancel_payment
    @message = 'Payment was cancelled. You can try again anytime.'
  end

  def cancel
    @subscription = current_user.subscription

    unless @subscription&.active_or_trial?
      redirect_to subscriptions_path, alert: 'No active subscription to cancel'
      return
    end

    # Cancel the Stripe subscription using service
    subscription_service = StripeSubscriptionService.new(current_user)

    if subscription_service.cancel_subscription(immediate: false)
      redirect_to subscriptions_path, notice: 'Subscription cancelled successfully!'
    else
      redirect_to subscriptions_path, alert: 'Error cancelling subscription. Please try again or contact support.'
    end
  end

end