class ApplicationController < ActionController::Base
  before_action :authenticate_user!, unless: :devise_controller? # Skip auth for Devise controllers
  before_action :configure_permitted_parameters, if: :devise_controller?
  before_action :set_request_id
  before_action :check_subscription_status, unless: :devise_controller?
  
  # Standard Rails error handling
  rescue_from StandardError, with: :handle_standard_error
  rescue_from ActiveRecord::RecordNotFound, with: :handle_not_found
  
  # Check if admin is impersonating a user
  def admin_impersonating?
    session[:admin_impersonating_user_id].present?
  end
  helper_method :admin_impersonating?
  
  # Get the admin user who is impersonating
  def impersonating_admin_user
    return nil unless admin_impersonating?
    AdminUser.find_by(id: session[:admin_user_id])
  end
  helper_method :impersonating_admin_user
  
  # Create audit log entry
  def create_audit_log(action, metadata = {})
    AuditLog.create_entry(
      action: action,
      user: current_user,
      ip_address: request.remote_ip,
      metadata: metadata.merge(
        user_agent: request.user_agent,
        controller: controller_name,
        action_name: action_name
      )
    )
  end
  
  protected
  
  def configure_permitted_parameters
    devise_parameter_sanitizer.permit(:sign_up, keys: [:first_name, :last_name, :timezone, :marketing_emails])
    devise_parameter_sanitizer.permit(:account_update, keys: [:first_name, :last_name, :timezone, :marketing_emails])
  end
  
  private

  def set_request_id
    Thread.current[:request_id] = request.uuid
  end

  def check_subscription_status
    return unless user_signed_in?
    return if admin_impersonating? # Allow admin impersonation to bypass payment

    # Skip check if user has active subscription
    return if current_user.has_active_subscription?

    # Use Stripe payment link configured in dashboard
    # Success URL must be configured in Stripe Dashboard -> Payment Links
    payment_link = ENV['STRIPE_STANDARD_PAYMENT_LINK'] || 'https://buy.stripe.com/test_placeholder'

    # Redirect to payment page with message
    flash[:alert] = "Please complete your subscription to access the application."
    redirect_to payment_link, allow_other_host: true
  end
  
  def handle_standard_error(error)
    Rails.logger.error "Unhandled error: #{error.message}"
    Rails.logger.error error.backtrace.join("\n")
    
    if Rails.env.production?
      redirect_to '/500'
    else
      raise error
    end
  end
  
  def handle_not_found(error)
    Rails.logger.warn "Record not found: #{error.message}"
    
    respond_to do |format|
      format.html { redirect_to '/404' }
      format.json { render json: { error: 'Not Found' }, status: 404 }
    end
  end
end
