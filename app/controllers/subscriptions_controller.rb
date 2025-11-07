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

    # Create Checkout Session using service
    checkout_service = StripeCheckoutService.new(
      current_user,
      success_url: success_subscriptions_url,
      cancel_url: cancel_payment_subscriptions_url
    )

    checkout_url = checkout_service.create_checkout_session

    if checkout_url
      redirect_to checkout_url, allow_other_host: true
    else
      redirect_to subscriptions_path, alert: 'Payment system unavailable. Please try again later.'
    end
  end

  def create
    # Check if user already has active subscription
    if current_user.has_active_subscription?
      redirect_to subscriptions_path, alert: 'You already have an active subscription'
      return
    end

    # Create Checkout Session using service
    checkout_service = StripeCheckoutService.new(
      current_user,
      success_url: success_subscriptions_url,
      cancel_url: cancel_payment_subscriptions_url
    )

    checkout_url = checkout_service.create_checkout_session

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

end