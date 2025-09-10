FactoryBot.define do
  factory :subscription do
    association :user
    status { 'paid' }
    stripe_subscription_id { 'sub_paid_123' }
    current_period_start { 1.month.ago }
    current_period_end { 1.month.from_now }
    
    trait :paid do
      status { 'paid' }
      stripe_subscription_id { 'sub_paid_123' }
      current_period_start { 1.month.ago }
      current_period_end { 1.month.from_now }
    end
    
    trait :canceled do
      status { 'paid' }
      stripe_subscription_id { 'sub_paid_123' }
      canceled_at { 1.day.ago }
      current_period_start { 1.month.ago }
      current_period_end { 1.week.from_now }
    end
  end
end