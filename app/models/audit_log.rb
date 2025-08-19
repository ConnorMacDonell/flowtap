class AuditLog < ApplicationRecord
  belongs_to :user, optional: true
  
  validates :action, presence: true
  validates :ip_address, format: { with: /\A(?:[0-9]{1,3}\.){3}[0-9]{1,3}\z|\A(?:[0-9a-fA-F]{1,4}:){7}[0-9a-fA-F]{1,4}\z/ }, allow_blank: true
  
  scope :recent, -> { order(created_at: :desc) }
  scope :for_user, ->(user) { where(user: user) }
  scope :for_action, ->(action) { where(action: action) }
  scope :security_events, -> { where("action LIKE '%security%' OR action LIKE '%login%' OR action LIKE '%admin%'") }
  
  # Audit log actions
  ACTIONS = {
    # Authentication events
    user_login: 'user_login',
    user_logout: 'user_logout',
    user_register: 'user_register',
    password_reset: 'password_reset',
    email_verified: 'email_verified',
    
    # Account management
    profile_updated: 'profile_updated',
    email_changed: 'email_changed',
    account_deleted: 'account_deleted',
    
    # Subscription events
    subscription_created: 'subscription_created',
    subscription_updated: 'subscription_updated',
    subscription_canceled: 'subscription_canceled',
    payment_succeeded: 'payment_succeeded',
    payment_failed: 'payment_failed',
    
    # Admin events
    admin_login: 'admin_login',
    admin_logout: 'admin_logout',
    user_impersonated: 'user_impersonated',
    user_suspended: 'user_suspended',
    user_unsuspended: 'user_unsuspended',
    
    # Security events
    failed_login_attempt: 'failed_login_attempt',
    suspicious_activity: 'suspicious_activity',
    data_export_requested: 'data_export_requested'
  }.freeze
  
  # Create audit log entry
  def self.create_entry(action:, user: nil, ip_address: nil, metadata: {})
    create!(
      action: action,
      user: user,
      ip_address: ip_address,
      metadata: metadata
    )
  rescue StandardError => e
    Rails.logger.error "Failed to create audit log: #{e.message}"
  end
  
  # Get formatted action name for display
  def action_display_name
    action.humanize.titleize
  end
  
  # Check if this is a security-related event
  def security_event?
    action.include?('security') || action.include?('login') || action.include?('admin')
  end
  
  # Get user display name
  def user_display_name
    return 'System' unless user
    user.full_name.presence || user.email
  end
end