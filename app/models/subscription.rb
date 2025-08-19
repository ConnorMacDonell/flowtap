class Subscription < ApplicationRecord
  belongs_to :user

  TIERS = {
    'free' => { 
      name: 'Free', 
      price: 0, 
      features: ['Basic features', 'Email support', 'Up to 5 projects'] 
    },
    'standard' => { 
      name: 'Standard', 
      price: 19, 
      features: ['All Free features', 'Priority support', 'Up to 25 projects', 'Advanced analytics'] 
    },
    'premium' => { 
      name: 'Premium', 
      price: 49, 
      features: ['All Standard features', '24/7 phone support', 'Unlimited projects', 'Custom integrations'] 
    }
  }.freeze

  validates :status, presence: true, inclusion: { in: TIERS.keys }
  validates :stripe_subscription_id, uniqueness: true, allow_nil: true

  scope :active, -> { where.not(status: 'canceled') }
  scope :canceled, -> { where(status: 'canceled') }
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

  def free?
    status == 'free'
  end

  def standard?
    status == 'standard'
  end

  def premium?
    status == 'premium'
  end

  def active?
    !canceled?
  end

  def canceled?
    canceled_at.present?
  end

  def monthly_price
    tier_price
  end

  def can_upgrade_to?(target_tier)
    return false unless TIERS.key?(target_tier)
    return false if status == target_tier
    
    tier_order = ['free', 'standard', 'premium']
    current_index = tier_order.index(status)
    target_index = tier_order.index(target_tier)
    
    target_index > current_index
  end
end
