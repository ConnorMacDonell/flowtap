class Admin::UsersController < Admin::BaseController
  before_action :set_user, only: [:show, :edit, :update, :impersonate, :suspend, :unsuspend, :verify]
  
  def index
    @q = User.includes(:subscription).ransack(params[:q])
    @users = @q.result.page(params[:page]).per(25).order(created_at: :desc)
    
    # Filter options
    @filter_verified = params[:verified]
    @filter_subscription = params[:subscription]
    
    # Apply filters
    @users = @users.where.not(confirmed_at: nil) if @filter_verified == 'true'
    @users = @users.where(confirmed_at: nil) if @filter_verified == 'false'
    
    if @filter_subscription.present?
      @users = @users.joins(:subscription).where(subscriptions: { status: @filter_subscription })
    end
    
    # Statistics for the current filter
    @stats = {
      total: @users.count,
      verified: @users.where.not(confirmed_at: nil).count,
      unverified: @users.where(confirmed_at: nil).count,
      deleted: @users.where.not(deleted_at: nil).count
    }
  end
  
  def show
    @audit_logs = [] # TODO: Implement audit logging
    @subscription_history = [@user.subscription] # TODO: Expand when subscription changes are tracked
  end
  
  def edit
    # Edit form for user details
  end
  
  def update
    if @user.update(user_params)
      redirect_to admin_user_path(@user), notice: 'User was successfully updated.'
    else
      render :edit
    end
  end
  
  def impersonate
    session[:admin_impersonating_user_id] = @user.id
    session[:admin_user_id] = current_admin_user.id
    
    # Log this action
    Rails.logger.info "Admin #{current_admin_user.email} is impersonating user #{@user.email}"
    
    # Sign in as the user
    sign_in(@user, scope: :user)
    redirect_to dashboard_path, notice: "You are now impersonating #{@user.full_name.presence || @user.email}. Click 'Stop Impersonating' to return to admin."
  end
  
  def stop_impersonating
    if session[:admin_impersonating_user_id]
      impersonated_user_id = session[:admin_impersonating_user_id]
      admin_user_id = session[:admin_user_id]
      
      # Clear the impersonation session
      session.delete(:admin_impersonating_user_id)
      session.delete(:admin_user_id)
      
      # Log this action
      Rails.logger.info "Stopped impersonating user ID #{impersonated_user_id}"
      
      # Sign out the impersonated user and sign back in as admin
      sign_out(:user)
      admin_user = AdminUser.find(admin_user_id)
      sign_in(admin_user, scope: :admin_user)
      
      redirect_to admin_users_path, notice: 'Stopped impersonating user.'
    else
      redirect_to admin_users_path, alert: 'No impersonation session found.'
    end
  end
  
  def suspend
    @user.update!(deleted_at: Time.current)
    
    # Log this action
    Rails.logger.info "Admin #{current_admin_user.email} suspended user #{@user.email}"
    
    redirect_to admin_user_path(@user), notice: 'User has been suspended.'
  end
  
  def unsuspend
    @user.update!(deleted_at: nil)
    
    # Log this action
    Rails.logger.info "Admin #{current_admin_user.email} unsuspended user #{@user.email}"
    
    redirect_to admin_user_path(@user), notice: 'User has been unsuspended.'
  end
  
  def verify
    @user.update!(confirmed_at: Time.current, confirmation_token: nil)
    
    # Log this action
    Rails.logger.info "Admin #{current_admin_user.email} manually verified user #{@user.email}"
    
    redirect_to admin_user_path(@user), notice: 'User has been manually verified.'
  end
  
  private
  
  def set_user
    @user = User.find(params[:id])
  end
  
  def user_params
    params.require(:user).permit(:first_name, :last_name, :email, :timezone, :marketing_emails)
  end
end