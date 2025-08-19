class ApplicationController < ActionController::Base
  before_action :authenticate_user!, unless: :devise_controller? # Skip auth for Devise controllers
  before_action :configure_permitted_parameters, if: :devise_controller?
  before_action :set_request_id
  
  # Custom error handling
  rescue_from StandardError, with: :handle_standard_error
  rescue_from ApplicationError, with: :handle_application_error
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
  
  def handle_standard_error(error)
    log_error("Unhandled error: #{error.message}", {
      error_class: error.class.name,
      backtrace: error.backtrace.first(5)
    })
    
    if Rails.env.production?
      redirect_to '/500'
    else
      raise error
    end
  end
  
  def handle_application_error(error)
    log_error("Application error: #{error.message}", {
      error_code: error.error_code,
      user_message: error.user_message
    })
    
    flash[:alert] = error.user_message
    redirect_back(fallback_location: root_path)
  end
  
  def handle_not_found(error)
    log_warn("Record not found: #{error.message}")
    
    respond_to do |format|
      format.html { redirect_to '/404' }
      format.json { render json: { error: 'Not Found' }, status: 404 }
    end
  end
end
