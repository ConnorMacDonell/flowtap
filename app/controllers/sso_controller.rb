# Controller for handling QuickBooks App Store SSO flows
# Handles Launch URL and Disconnect landing page requirements
class SsoController < ApplicationController
  skip_before_action :authenticate_user!, only: [:launch, :disconnected]

  # Launch URL - Called when users click "Launch" from QuickBooks App Store
  # Requirements:
  # - If user already signed in → redirect to dashboard
  # - If user has Intuit SSO session → auto-sign in via QBO SSO
  # - If no session → initiate QBO SSO flow (user may need to authenticate)
  def launch
    # If user is already signed in, just send them to dashboard
    if user_signed_in?
      Rails.logger.info "SSO Launch: User #{current_user.id} already signed in, redirecting to dashboard"
      redirect_to dashboard_path, notice: 'Welcome back!'
      return
    end

    # User not signed in - initiate QBO SSO flow
    # This will:
    # 1. Check if user has active Intuit session
    # 2. Auto-sign in existing users
    # 3. Create new users if needed
    # 4. All without requiring manual button clicks
    Rails.logger.info "SSO Launch: Initiating QBO SSO flow for unauthenticated user"
    redirect_to auth_qbo_sso_connect_path, allow_other_host: true
  end

  # Disconnect landing page - Called when users disconnect from QuickBooks App Store
  # Requirements:
  # - Show message about disconnection
  # - Display "Sign in with Intuit" button
  # - Display "Connect to QuickBooks" button
  # - Implements Intuit Single Sign-on for easy reconnection
  def disconnected
    Rails.logger.info "SSO Disconnect: User landed on disconnect page"
    # View will render the disconnect landing page
  end
end
