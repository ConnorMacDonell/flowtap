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
  after_create :create_free_subscription
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
    subscription&.status || 'free'
  end

  def subscription_tier_name
    subscription&.tier_name || 'Free'
  end

  def can_access_feature?(feature)
    case subscription_tier
    when 'free'
      ['basic_features'].include?(feature)
    when 'standard'
      ['basic_features', 'advanced_analytics', 'priority_support'].include?(feature)
    when 'premium'
      true # Premium users get all features
    else
      false
    end
  end

  private

  def create_free_subscription
    build_subscription(status: 'free').save!
  end
  
  def send_welcome_email
    return unless confirmed_at.present? && confirmed_at_previously_changed?
    EmailJob.perform_later('UserMailer', 'welcome_email', id)
  end
end
