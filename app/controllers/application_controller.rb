class ApplicationController < ActionController::Base
  before_action :authenticate_user!, unless: :devise_controller? # Skip auth for Devise controllers
  before_action :configure_permitted_parameters, if: :devise_controller?
  before_action :set_request_id
  before_action :check_subscription_status, unless: :devise_controller?
  after_action :set_cache_headers
  
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

  # Security: Prevent sensitive data from being cached by browsers/proxies
  # Required by Intuit security requirements for QBO integration
  def set_cache_headers
    # Use Rails' CacheControl API (the Rails way)
    # This works with Rails' caching middleware and won't be overwritten
    response.cache_control.merge!(
      no_cache: true,
      no_store: true,
      must_revalidate: true,
      public: false
    )

    # Set additional headers for HTTP/1.0 compatibility
    response.headers['Pragma'] = 'no-cache'
    response.headers['Expires'] = '0'
  end

  def check_subscription_status
    return unless user_signed_in?
    return if admin_impersonating? # Allow admin impersonation to bypass payment

    # Skip check if user has active subscription
    return if current_user.has_active_subscription?

    # Redirect to subscription page which will create checkout session
    flash[:alert] = "Please complete your subscription to access the application."
    redirect_to new_subscription_path
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
