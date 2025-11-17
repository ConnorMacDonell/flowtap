require 'rails_helper'

RSpec.describe Subscription, type: :model do
  describe 'associations' do
    it 'belongs to user' do
      subscription = create(:subscription)
      expect(subscription.user).to be_present
    end
  end

  describe 'validations' do
    it 'validates presence of status' do
      subscription = build(:subscription, status: nil)
      expect(subscription).not_to be_valid
      expect(subscription.errors[:status]).to be_present
    end

    it 'validates inclusion of status' do
      subscription = build(:subscription, status: 'invalid')
      expect(subscription).not_to be_valid
      expect(subscription.errors[:status]).to include('is not included in the list')
    end
  end

  describe '#qbo_sso_free_trial?' do
    context 'when user is a QBO SSO user' do
      let(:user) { create(:user, qbo_sub_id: 'qbo_sub_123') }
      let(:subscription) { create(:subscription, user: user) }

      context 'when subscription is less than 14 days old' do
        it 'returns true' do
          expect(subscription.qbo_sso_free_trial?).to be true
        end
      end

      context 'when subscription is exactly 13 days old' do
        it 'returns true' do
          subscription.update!(created_at: 13.days.ago)
          expect(subscription.qbo_sso_free_trial?).to be true
        end
      end

      context 'when subscription is 14 days old' do
        it 'returns false' do
          subscription.update!(created_at: 14.days.ago)
          expect(subscription.qbo_sso_free_trial?).to be false
        end
      end

      context 'when subscription is older than 14 days' do
        it 'returns false' do
          subscription.update!(created_at: 15.days.ago)
          expect(subscription.qbo_sso_free_trial?).to be false
        end
      end
    end

    context 'when user is not a QBO SSO user' do
      let(:user) { create(:user, qbo_sub_id: nil) }
      let(:subscription) { create(:subscription, user: user) }

      it 'returns false even if subscription is less than 14 days old' do
        expect(subscription.qbo_sso_free_trial?).to be false
      end

      it 'returns false when subscription is older than 14 days' do
        subscription.update!(created_at: 15.days.ago)
        expect(subscription.qbo_sso_free_trial?).to be false
      end
    end

    context 'when subscription has no created_at timestamp' do
      let(:user) { create(:user, qbo_sub_id: 'qbo_sub_123') }
      let(:subscription) { build(:subscription, user: user, created_at: nil) }

      it 'returns false' do
        expect(subscription.qbo_sso_free_trial?).to be false
      end
    end

    context 'when subscription has no associated user' do
      let(:subscription) { build(:subscription, user: nil) }

      it 'returns false' do
        expect(subscription.qbo_sso_free_trial?).to be false
      end
    end
  end

  describe '#active_or_trial?' do
    let(:user) { create(:user) }
    let(:subscription) { create(:subscription, user: user) }

    context 'when subscription status is paid' do
      it 'returns true' do
        subscription.update!(status: 'paid')
        expect(subscription.active_or_trial?).to be true
      end
    end

    context 'when subscription is on QBO SSO trial' do
      let(:qbo_user) { create(:user, qbo_sub_id: 'qbo_sub_123') }
      let(:trial_subscription) { create(:subscription, user: qbo_user, status: 'inactive') }

      it 'returns true' do
        expect(trial_subscription.active_or_trial?).to be true
      end
    end

    context 'when subscription is inactive and NOT on trial' do
      it 'returns false' do
        subscription.update!(status: 'inactive', created_at: 15.days.ago)
        expect(subscription.active_or_trial?).to be false
      end
    end

    context 'when subscription is canceled' do
      it 'returns false' do
        subscription.update!(status: 'canceled')
        expect(subscription.active_or_trial?).to be false
      end

      it 'returns false even if it would qualify for trial' do
        qbo_user = create(:user, qbo_sub_id: 'qbo_sub_123')
        canceled_trial = create(:subscription, user: qbo_user, status: 'canceled')

        # Even though it's a QBO user with recent subscription
        expect(canceled_trial.qbo_sso_free_trial?).to be true
        # Canceled status overrides trial
        expect(canceled_trial.active_or_trial?).to be false
      end
    end

    context 'when email/password user has inactive subscription' do
      let(:email_user) { create(:user, qbo_sub_id: nil) }
      let(:email_subscription) { create(:subscription, user: email_user, status: 'inactive') }

      it 'returns false' do
        expect(email_subscription.active_or_trial?).to be false
      end
    end
  end

  describe '#active?' do
    let(:subscription) { create(:subscription) }

    it 'returns true when status is paid' do
      subscription.update!(status: 'paid')
      expect(subscription.active?).to be true
    end

    it 'returns false when status is inactive' do
      subscription.update!(status: 'inactive')
      expect(subscription.active?).to be false
    end

    it 'returns false when status is canceled' do
      subscription.update!(status: 'canceled')
      expect(subscription.active?).to be false
    end
  end

  describe '#paid?' do
    let(:subscription) { create(:subscription) }

    it 'returns true when status is paid' do
      subscription.update!(status: 'paid')
      expect(subscription.paid?).to be true
    end

    it 'returns false when status is inactive' do
      subscription.update!(status: 'inactive')
      expect(subscription.paid?).to be false
    end
  end

  describe '#canceled?' do
    let(:subscription) { create(:subscription) }

    it 'returns true when status is canceled' do
      subscription.update!(status: 'canceled')
      expect(subscription.canceled?).to be true
    end

    it 'returns false when status is paid' do
      subscription.update!(status: 'paid')
      expect(subscription.canceled?).to be false
    end
  end

  describe '#inactive?' do
    let(:subscription) { create(:subscription) }

    it 'returns true when status is inactive' do
      subscription.update!(status: 'inactive')
      expect(subscription.inactive?).to be true
    end

    it 'returns false when status is paid' do
      subscription.update!(status: 'paid')
      expect(subscription.inactive?).to be false
    end
  end

  describe 'trial expiration scenarios' do
    context 'QBO SSO user trial lifecycle' do
      let(:qbo_user) { create(:user, qbo_sub_id: 'qbo_sub_123', email: 'qbo@example.com') }
      let(:subscription) { create(:subscription, user: qbo_user, status: 'inactive') }

      it 'progresses through trial states correctly' do
        # Day 1: Active trial
        expect(subscription.qbo_sso_free_trial?).to be true
        expect(subscription.active_or_trial?).to be true
        expect(subscription.active?).to be false

        # Day 13: Still in trial
        subscription.update!(created_at: 13.days.ago)
        expect(subscription.qbo_sso_free_trial?).to be true
        expect(subscription.active_or_trial?).to be true

        # Day 14: Trial expired
        subscription.update!(created_at: 14.days.ago)
        expect(subscription.qbo_sso_free_trial?).to be false
        expect(subscription.active_or_trial?).to be false
        expect(subscription.active?).to be false

        # After payment: Converted to paid
        subscription.update!(status: 'paid')
        expect(subscription.qbo_sso_free_trial?).to be false  # No longer on trial
        expect(subscription.active_or_trial?).to be true      # But active via paid status
        expect(subscription.active?).to be true
      end
    end

    context 'email/password user (no trial)' do
      let(:email_user) { create(:user, qbo_sub_id: nil, email: 'email@example.com') }
      let(:subscription) { create(:subscription, user: email_user, status: 'inactive') }

      it 'never qualifies for QBO SSO trial' do
        # Day 1
        expect(subscription.qbo_sso_free_trial?).to be false
        expect(subscription.active_or_trial?).to be false
        expect(subscription.active?).to be false

        # After payment
        subscription.update!(status: 'paid')
        expect(subscription.qbo_sso_free_trial?).to be false
        expect(subscription.active_or_trial?).to be true
        expect(subscription.active?).to be true
      end
    end
  end
end
