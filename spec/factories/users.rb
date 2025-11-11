FactoryBot.define do
  factory :user do
    sequence(:email) { |n| "user#{n}@example.com" }
    password { 'password123' }
    first_name { 'John' }
    last_name { 'Doe' }
    timezone { 'UTC' }
    confirmed_at { Time.current }
    eula_accepted { true }
    eula_accepted_at { Time.current }
    privacy_policy_accepted_at { Time.current }

    # Create paid subscription by default since all users need one to use the site
    after(:create) do |user, evaluator|
      create(:subscription, user: user, status: 'paid') unless evaluator.without_subscription
    end

    # Use this trait when testing users without subscriptions
    transient do
      without_subscription { false }
    end

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

    trait :with_freelancer_connection do
      freelancer_user_id { "freelancer_#{SecureRandom.hex(8)}" }
      freelancer_access_token { 'freelancer_access_token_123' }
      freelancer_refresh_token { 'freelancer_refresh_token_123' }
      freelancer_token_expires_at { 30.days.from_now }
      freelancer_scopes { 'basic 1 2 3 4 5 6 7 8' }
      freelancer_connected_at { Time.current }
    end

    trait :with_freelancer_valid_token do
      freelancer_user_id { "freelancer_#{SecureRandom.hex(8)}" }
      freelancer_access_token { 'valid_access_token' }
      freelancer_refresh_token { 'valid_refresh_token' }
      freelancer_token_expires_at { 14.days.from_now }
      freelancer_scopes { 'basic 1 2 3 4 5 6 7 8' }
      freelancer_connected_at { Time.current }
    end

    trait :with_expired_freelancer_token do
      freelancer_user_id { "freelancer_#{SecureRandom.hex(8)}" }
      freelancer_access_token { 'freelancer_access_token_123' }
      freelancer_refresh_token { 'freelancer_refresh_token_123' }
      freelancer_token_expires_at { 1.hour.ago }
      freelancer_scopes { 'basic 1 2 3' }
      freelancer_connected_at { 1.day.ago }
    end

    trait :with_freelancer_expiring_token do
      freelancer_user_id { "freelancer_#{SecureRandom.hex(8)}" }
      freelancer_access_token { 'expiring_access_token' }
      freelancer_refresh_token { 'refresh_token_123' }
      freelancer_token_expires_at { 3.days.from_now }
      freelancer_scopes { 'basic 1 2 3' }
      freelancer_connected_at { Time.current }
    end

    trait :with_expired_freelancer_refresh_token do
      freelancer_user_id { "freelancer_#{SecureRandom.hex(8)}" }
      freelancer_access_token { 'expired_access_token' }
      freelancer_refresh_token { 'expired_refresh_token' }
      freelancer_token_expires_at { 1.hour.ago }
      freelancer_scopes { 'basic 1 2 3' }
      freelancer_connected_at { 7.months.ago }
    end
  end
end