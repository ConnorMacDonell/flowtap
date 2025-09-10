class Subscription < ApplicationRecord
  belongs_to :user

  TIERS = {
    'paid' => { 
      name: 'Pro', 
      price: 29, 
      features: ['All features included', 'Priority support', 'Unlimited projects', 'Advanced analytics', 'Custom integrations'] 
    }
  }.freeze

  STATUSES = ['paid', 'canceled', 'inactive'].freeze

  validates :status, presence: true, inclusion: { in: STATUSES }
  validates :stripe_subscription_id, uniqueness: true, allow_nil: true

  scope :active, -> { where(status: 'paid') }
  scope :canceled, -> { where(status: 'canceled') }
  scope :inactive, -> { where(status: 'inactive') }
  scope :by_tier, ->(tier) { where(status: tier) }

  def tier_name
    TIERS.dig(status, :name)
  end

  def tier_price
    TIERS.dig(status, :price)
  end

  def tier_features
    TIERS.dig(status, :features) || []
  end

  def paid?
    status == 'paid'
  end

  def active?
    status == 'paid'
  end

  def canceled?
    status == 'canceled'
  end

  def inactive?
    status == 'inactive'
  end

  def monthly_price
    tier_price
  end

end
