FactoryBot.define do
  factory :subscription do
    association :user
    status { 'paid' }
    sequence(:stripe_subscription_id) { |n| "sub_test_#{n}" }
    current_period_start { 1.month.ago }
    current_period_end { 1.month.from_now }

    trait :paid do
      status { 'paid' }
      sequence(:stripe_subscription_id) { |n| "sub_paid_#{n}" }
      current_period_start { 1.month.ago }
      current_period_end { 1.month.from_now }
    end

    trait :canceled do
      status { 'paid' }
      sequence(:stripe_subscription_id) { |n| "sub_canceled_#{n}" }
      canceled_at { 1.day.ago }
      current_period_start { 1.month.ago }
      current_period_end { 1.week.from_now }
    end
  end
end
