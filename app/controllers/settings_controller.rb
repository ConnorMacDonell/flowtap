class SettingsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_user

  def index
    # Main settings page
  end

  def account
    # Account specific settings
  end

  def notifications
    # Notification preferences
  end

  def security
    # Security settings and audit log
    @recent_activity = @user.audit_logs.recent.limit(10) if defined?(AuditLog)
  end

  def export_data
    # Export user data (GDPR compliance)
    respond_to do |format|
      format.html
      format.json { render json: user_data_export }
    end
  end

  def delete_account
    # Account deletion confirmation page
  end

  def update_notifications
    if @user.update(notification_params)
      redirect_to settings_notifications_path, notice: 'Notification preferences updated successfully.'
    else
      render :notifications, alert: 'Unable to update notification preferences.'
    end
  end

  private

  def set_user
    @user = current_user
  end

  def notification_params
    params.require(:user).permit(:marketing_emails)
  end

  def user_data_export
    {
      user: @user.as_json(except: [:encrypted_password, :reset_password_token, :confirmation_token]),
      account_created: @user.created_at,
      last_sign_in: @user.last_sign_in_at,
      total_sign_ins: @user.sign_in_count,
      subscription: (@user.respond_to?(:subscription) ? @user.subscription&.as_json(except: [:stripe_subscription_id]) : nil),
      exported_at: Time.current
    }
  end
end