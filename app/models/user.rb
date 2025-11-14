class User < ApplicationRecord
  # Include default devise modules. Others available are:
  # :lockable, :timeoutable and :omniauthable
  devise :database_authenticatable, :registerable,
         :recoverable, :rememberable, :validatable,
         :confirmable, :trackable

  # Encrypt sensitive OAuth tokens
  encrypts :qbo_access_token
  encrypts :qbo_refresh_token
  encrypts :qbo_id_token
  encrypts :freelancer_access_token
  encrypts :freelancer_refresh_token

  # Associations
  has_one :subscription, dependent: :destroy
  has_many :audit_logs, dependent: :nullify

  # Validations
  validates :first_name, presence: true, length: { maximum: 50 }
  validates :last_name, presence: true, length: { maximum: 50 }
  validates :timezone, presence: true

  # Callbacks
  after_update :send_welcome_email, if: :confirmed_at_previously_changed?

  # Scopes
  scope :confirmed, -> { where.not(confirmed_at: nil) }
  scope :unconfirmed, -> { where(confirmed_at: nil) }
  scope :not_deleted, -> { where(deleted_at: nil) }
  scope :deleted, -> { where.not(deleted_at: nil) }

  # Soft delete
  def soft_delete!
    # Step 1: Revoke OAuth tokens BEFORE deleting account
    revoke_oauth_tokens_on_deletion

    # Step 2: Cancel Stripe subscription
    # This is synchronous and will raise an error if it fails
    if subscription&.stripe_subscription_id.present?
      service = StripeSubscriptionService.new(self)
      begin
        service.cancel_subscription(immediate: true)
      rescue Stripe::StripeError => e
        # If Stripe cancellation fails, prevent account deletion
        raise ActiveRecord::RecordInvalid.new(self),
              "Cannot delete account: Failed to cancel subscription. Please try again later or contact support."
      end
    end

    # Step 3: Clear OAuth data from database
    clear_oauth_data_on_deletion

    # Step 4: Mark account as deleted
    update!(deleted_at: Time.current)
  end

  def deleted?
    deleted_at.present?
  end

  def active_for_authentication?
    super && !deleted?
  end

  def inactive_message
    deleted? ? :deleted_account : super
  end

  # Name helpers
  def full_name
    "#{first_name} #{last_name}".strip
  end

  def initials
    "#{first_name&.first}#{last_name&.first}".upcase
  end

  # Subscription helpers
  def subscription_tier
    subscription&.status || 'inactive'
  end

  def subscription_tier_name
    return 'Inactive' if subscription&.inactive?
    subscription&.tier_name || 'No Subscription'
  end

  def has_active_subscription?
    subscription&.active? || false
  end

  def can_access_feature?(feature)
    has_active_subscription?
  end

  # QBO SSO helpers
  def qbo_sso_user?
    qbo_sub_id.present?
  end

  # QBO integration helpers
  def qbo_connected?
    qbo_realm_id.present? && qbo_access_token.present?
  end

  def qbo_token_expired?
    qbo_token_expires_at.present? && qbo_token_expires_at < Time.current
  end

  def qbo_token_valid?
    qbo_connected? && !qbo_token_expired?
  end

  def qbo_token_expires_soon?
    qbo_token_expires_at.present? && qbo_token_expires_at <= 7.days.from_now
  end

  def qbo_needs_refresh?
    qbo_connected? && (qbo_token_expired? || qbo_token_expires_soon?)
  end

  def qbo_can_refresh?
    qbo_refresh_token.present? && qbo_connected_at.present? && qbo_connected_at > 180.days.ago
  end

  def qbo_refresh_token_expired?
    qbo_connected_at.blank? || qbo_connected_at <= 180.days.ago
  end

  def disconnect_qbo!
    update!(
      qbo_realm_id: nil,
      qbo_access_token: nil,
      qbo_refresh_token: nil,
      qbo_token_expires_at: nil,
      qbo_connected_at: nil,
      qbo_id_token: nil,
      qbo_sub_id: nil,
      qbo_user_email: nil,
      qbo_user_email_verified: nil,
      qbo_user_given_name: nil,
      qbo_user_family_name: nil
    )
  end

  # Freelancer integration helpers
  def freelancer_connected?
    freelancer_user_id.present? && freelancer_access_token.present?
  end

  def freelancer_token_expired?
    freelancer_token_expires_at.present? && freelancer_token_expires_at < Time.current
  end

  def freelancer_token_valid?
    freelancer_connected? && !freelancer_token_expired?
  end

  def freelancer_token_expires_soon?(days_threshold = 7)
    return false unless freelancer_token_expires_at.present?
    freelancer_token_expires_at <= days_threshold.days.from_now
  end

  def freelancer_refresh_token_expired?
    return true unless freelancer_refresh_token.present?
    # Assume refresh tokens expire after 6 months from connection
    return false unless freelancer_connected_at.present?
    freelancer_connected_at < 6.months.ago
  end

  def freelancer_needs_refresh?
    freelancer_connected? && (freelancer_token_expired? || freelancer_token_expires_soon?)
  end

  def freelancer_can_refresh?
    freelancer_refresh_token.present? && !freelancer_refresh_token_expired?
  end

  def freelancer_scopes_array
    return [] unless freelancer_scopes.present?
    freelancer_scopes.split(' ')
  end

  def has_freelancer_scope?(scope)
    freelancer_scopes_array.include?(scope.to_s)
  end

  def disconnect_freelancer!
    update!(
      freelancer_user_id: nil,
      freelancer_access_token: nil,
      freelancer_refresh_token: nil,
      freelancer_token_expires_at: nil,
      freelancer_scopes: nil,
      freelancer_connected_at: nil
    )
  end

  private

  # Override Devise method to make password optional for SSO users
  def password_required?
    return false if qbo_sso_user?
    super
  end

  def send_welcome_email
    return unless confirmed_at.present? && confirmed_at_previously_changed?
    UserMailer.welcome_email(self).deliver_now
    # EmailJob.perform_later('UserMailer', 'welcome_email', id)
  end

  # Revoke OAuth tokens with external providers before account deletion
  def revoke_oauth_tokens_on_deletion
    revoke_qbo_tokens_on_deletion
    revoke_freelancer_tokens_on_deletion
  end

  # Revoke QBO OAuth tokens with Intuit before deletion
  def revoke_qbo_tokens_on_deletion
    return unless qbo_connected?

    begin
      qbo_service = QboService.new(self)
      if qbo_service.revoke_tokens!
        Rails.logger.info("Account deletion: Successfully revoked QBO tokens for user #{id}")
      else
        Rails.logger.warn("Account deletion: Failed to revoke QBO tokens for user #{id}, proceeding with deletion")
      end
    rescue ArgumentError => e
      # QboService initialization failed (e.g., token already expired and can't refresh)
      Rails.logger.warn("Account deletion: QBO tokens already invalid for user #{id}: #{e.message}")
    rescue => e
      # Log error but don't block account deletion
      Rails.logger.error("Account deletion: Error revoking QBO tokens for user #{id}: #{e.message}")
    end
  end

  # Revoke Freelancer OAuth tokens before deletion
  # Note: Freelancer API doesn't provide a token revocation endpoint as of implementation
  # Tokens will expire naturally (access: 1 hour, refresh: 6 months)
  def revoke_freelancer_tokens_on_deletion
    return unless freelancer_connected?

    # TODO: Implement when Freelancer provides a revoke endpoint
    Rails.logger.info("Account deletion: Freelancer tokens for user #{id} will expire naturally (no revoke endpoint available)")
  end

  # Clear OAuth data from database after revocation
  def clear_oauth_data_on_deletion
    clear_qbo_data_on_deletion
    clear_freelancer_data_on_deletion
  end

  # Clear QBO OAuth data from database
  def clear_qbo_data_on_deletion
    return unless qbo_connected? || qbo_sso_user?

    update_columns(
      qbo_realm_id: nil,
      qbo_access_token: nil,
      qbo_refresh_token: nil,
      qbo_token_expires_at: nil,
      qbo_connected_at: nil,
      qbo_id_token: nil,
      qbo_sub_id: nil,
      qbo_user_email: nil,
      qbo_user_email_verified: nil,
      qbo_user_given_name: nil,
      qbo_user_family_name: nil
    )
    Rails.logger.info("Account deletion: Cleared QBO OAuth data for user #{id}")
  end

  # Clear Freelancer OAuth data from database
  def clear_freelancer_data_on_deletion
    return unless freelancer_connected?

    update_columns(
      freelancer_user_id: nil,
      freelancer_access_token: nil,
      freelancer_refresh_token: nil,
      freelancer_token_expires_at: nil,
      freelancer_scopes: nil,
      freelancer_connected_at: nil
    )
    Rails.logger.info("Account deletion: Cleared Freelancer OAuth data for user #{id}")
  end
end
