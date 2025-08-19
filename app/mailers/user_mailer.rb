class UserMailer < ApplicationMailer
  default from: ENV['DEFAULT_FROM_EMAIL'] || 'noreply@example.com'
  
  def welcome_email(user)
    @user = user
    @dashboard_url = dashboard_url
    @application_name = application_name
    @support_email = support_email
    
    mail(
      to: @user.email,
      subject: "Welcome to #{application_name}!"
    )
  end
  
  def confirmation_instructions(record, token, opts = {})
    @user = record
    @token = token
    @confirmation_url = user_confirmation_url(confirmation_token: @token)
    @application_name = application_name
    @support_email = support_email
    
    mail(
      to: @user.email,
      subject: 'Please confirm your email address'
    )
  end
  
  def reset_password_instructions(record, token, opts = {})
    @user = record
    @token = token
    @reset_password_url = edit_user_password_url(reset_password_token: @token)
    @application_name = application_name
    @support_email = support_email
    
    mail(
      to: @user.email,
      subject: 'Reset your password'
    )
  end
  
  def email_changed(record, opts = {})
    @user = record
    @new_email = @user.email
    @application_name = application_name
    @support_email = support_email
    
    mail(
      to: @user.email_was || @user.email,
      subject: 'Your email address has been changed'
    )
  end
  
  def account_deleted(user_data)
    @user_name = user_data[:name]
    @user_email = user_data[:email]
    @deletion_date = user_data[:deleted_at]
    @recovery_deadline = @deletion_date + 30.days
    @application_name = application_name
    @support_email = support_email
    
    mail(
      to: @user_email,
      subject: 'Your account has been deleted'
    )
  end
  
  def subscription_updated(user, old_tier, new_tier)
    @user = user
    @old_tier = old_tier
    @new_tier = new_tier
    @subscription_url = subscriptions_url
    @application_name = application_name
    @support_email = support_email
    
    mail(
      to: @user.email,
      subject: "Your subscription has been updated to #{new_tier.titleize}"
    )
  end
  
  def payment_failed(user, invoice_url = nil)
    @user = user
    @invoice_url = invoice_url
    @subscription_url = subscriptions_url
    @application_name = application_name
    @support_email = support_email
    
    mail(
      to: @user.email,
      subject: 'Payment failed - Action required'
    )
  end
  
  def trial_ending_reminder(user, days_remaining)
    @user = user
    @days_remaining = days_remaining
    @subscription_url = subscriptions_url
    @application_name = application_name
    @support_email = support_email
    
    mail(
      to: @user.email,
      subject: "Your trial ends in #{days_remaining} days"
    )
  end
  
  def data_export_ready(user, file_path)
    @user = user
    @file_path = file_path
    @filename = File.basename(file_path)
    @application_name = application_name
    @support_email = support_email
    
    mail(
      to: @user.email,
      subject: 'Your data export is ready'
    )
  end
  
  private
  
  def dashboard_url
    url_for(controller: 'dashboard', action: 'index', only_path: false)
  end
  
  def subscriptions_url
    url_for(controller: 'subscriptions', action: 'index', only_path: false)
  end
end