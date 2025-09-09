FactoryBot.define do
  factory :subscription do
    association :user
    status { 'free' }
    
    trait :free do
      status { 'free' }
    end
    
    trait :standard do
      status { 'standard' }
      stripe_subscription_id { 'sub_standard_123' }
      current_period_start { 1.month.ago }
      current_period_end { 1.month.from_now }
    end
    
    trait :premium do
      status { 'premium' }
      stripe_subscription_id { 'sub_premium_123' }
      current_period_start { 1.month.ago }
      current_period_end { 1.month.from_now }
    end
  end
end