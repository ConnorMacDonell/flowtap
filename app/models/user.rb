class User < ApplicationRecord
  # Include default devise modules. Others available are:
  # :lockable, :timeoutable and :omniauthable
  devise :database_authenticatable, :registerable,
         :recoverable, :rememberable, :validatable,
         :confirmable, :trackable

  # Associations
  has_one :subscription, dependent: :destroy

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

  def disconnect_qbo!
    update!(
      qbo_realm_id: nil,
      qbo_access_token: nil,
      qbo_refresh_token: nil,
      qbo_token_expires_at: nil,
      qbo_connected_at: nil
    )
  end

  private

  
  def send_welcome_email
    return unless confirmed_at.present? && confirmed_at_previously_changed?
    UserMailer.welcome_email(self).deliver_now
    # EmailJob.perform_later('UserMailer', 'welcome_email', id)
  end
end
