FactoryBot.define do
  factory :user do
    sequence(:email) { |n| "user#{n}@example.com" }
    password { 'password123' }
    first_name { 'John' }
    last_name { 'Doe' }
    timezone { 'UTC' }
    confirmed_at { Time.current }
    

    trait :with_paid_subscription do
      after(:create) do |user|
        create(:subscription, user: user, status: 'paid')
      end
    end

    trait :with_qbo_connection do
      qbo_realm_id { '123456789' }
      qbo_access_token { 'qbo_access_token_123' }
      qbo_refresh_token { 'qbo_refresh_token_123' }
      qbo_token_expires_at { 1.hour.from_now }
      qbo_connected_at { Time.current }
    end

    trait :with_expired_qbo_token do
      qbo_realm_id { '123456789' }
      qbo_access_token { 'qbo_access_token_123' }
      qbo_refresh_token { 'qbo_refresh_token_123' }
      qbo_token_expires_at { 1.hour.ago }
      qbo_connected_at { 1.day.ago }
    end
  end
end