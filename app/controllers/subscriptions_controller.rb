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
    @tier = params[:tier]
    @subscription = current_user.subscription
    
    # Validate tier parameter
    unless Subscription::TIERS.key?(@tier)
      redirect_to subscriptions_path, alert: 'Invalid subscription tier'
      return
    end

    # Check if user can upgrade to this tier
    unless @subscription.can_upgrade_to?(@tier)
      redirect_to subscriptions_path, alert: 'Cannot upgrade to this tier'
      return
    end

    # For now, block all paid tiers as specified in requirements
    if @tier != 'free'
      redirect_to subscriptions_path, alert: 'Paid subscriptions are coming soon!'
      return
    end
  end

  def create
    @tier = params[:tier]
    @subscription = current_user.subscription

    # Block all paid tiers as specified in requirements
    if @tier != 'free'
      redirect_to subscriptions_path, alert: 'Paid subscriptions are coming soon!'
      return
    end

    # In the future, this is where Stripe checkout would be handled
    # For now, just redirect back with message
    redirect_to subscriptions_path, notice: 'Subscription management coming soon!'
  end

  def cancel
    @subscription = current_user.subscription
    
    if @subscription.free?
      redirect_to subscriptions_path, alert: 'Cannot cancel free subscription'
      return
    end

    # For now, just show message since paid tiers are blocked
    redirect_to subscriptions_path, alert: 'Subscription cancellation coming soon!'
  end

  private

  def subscription_params
    params.require(:subscription).permit(:tier)
  end
end