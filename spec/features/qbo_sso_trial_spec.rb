require 'rails_helper'

RSpec.describe 'QBO SSO Trial Flow', type: :feature do
  describe 'QBO SSO user trial lifecycle' do
    let(:qbo_user) do
      create(:user,
        email: 'qbo_trial@example.com',
        qbo_sub_id: 'qbo_sub_trial_123',
        confirmed_at: Time.current,
        without_subscription: true
      )
    end

    let!(:trial_subscription) do
      create(:subscription, user: qbo_user, status: 'inactive')
    end

    context 'during active trial period (< 14 days)' do
      before do
        sign_in qbo_user
      end

      it 'allows access to dashboard' do
        visit dashboard_path
        expect(page).to have_current_path(dashboard_path)
        expect(page).to have_content('Welcome back')
      end

      it 'user has active subscription via trial' do
        expect(qbo_user.reload.has_active_subscription?).to be true
        expect(trial_subscription.reload.qbo_sso_free_trial?).to be true
        expect(trial_subscription.active_or_trial?).to be true
      end

      it 'does not redirect to subscription page' do
        visit dashboard_path
        expect(page).not_to have_current_path(new_subscription_path)
        expect(page).not_to have_content('Please complete your subscription')
      end
    end

    context 'on day 13 of trial' do
      before do
        trial_subscription.update!(created_at: 13.days.ago)
        sign_in qbo_user
      end

      it 'still has access to dashboard' do
        visit dashboard_path
        expect(page).to have_current_path(dashboard_path)
        expect(qbo_user.reload.has_active_subscription?).to be true
      end
    end

    context 'when trial expires (day 14+)' do
      before do
        trial_subscription.update!(created_at: 14.days.ago)
        sign_in qbo_user
      end

      it 'redirects to subscription page when accessing dashboard' do
        visit dashboard_path
        expect(page).to have_current_path(new_subscription_path)
      end

      it 'shows subscription required message' do
        visit dashboard_path
        expect(page).to have_content('Please complete your subscription')
      end

      it 'user no longer has active subscription' do
        expect(qbo_user.reload.has_active_subscription?).to be false
        expect(trial_subscription.reload.qbo_sso_free_trial?).to be false
        expect(trial_subscription.active_or_trial?).to be false
      end

      it 'can view subscription page without redirect loop' do
        visit new_subscription_path
        expect(page).to have_current_path(new_subscription_path)
        expect(page).to have_content('Welcome to FlowTap Pro')
      end
    end

    context 'after converting trial to paid subscription' do
      before do
        trial_subscription.update!(
          created_at: 20.days.ago,  # Old trial
          status: 'paid',            # Now paid
          stripe_subscription_id: 'sub_123'
        )
        sign_in qbo_user
      end

      it 'regains access to dashboard' do
        visit dashboard_path
        expect(page).to have_current_path(dashboard_path)
        expect(page).to have_content('Welcome back')
      end

      it 'has active subscription via paid status' do
        expect(qbo_user.reload.has_active_subscription?).to be true
        expect(trial_subscription.reload.qbo_sso_free_trial?).to be false  # No longer on trial
        expect(trial_subscription.active_or_trial?).to be true             # But still active
        expect(trial_subscription.active?).to be true                       # Via paid status
      end
    end
  end

  describe 'Email/password user (no trial)' do
    let(:email_user) do
      create(:user,
        email: 'email@example.com',
        qbo_sub_id: nil,
        confirmed_at: Time.current,
        without_subscription: true
      )
    end

    context 'without subscription' do
      before do
        sign_in email_user
      end

      it 'immediately redirects to subscription page' do
        visit dashboard_path
        expect(page).to have_current_path(new_subscription_path)
      end

      it 'does not have active subscription' do
        expect(email_user.reload.has_active_subscription?).to be false
      end
    end

    context 'with inactive subscription (should never happen in normal flow)' do
      let!(:inactive_subscription) do
        create(:subscription, user: email_user, status: 'inactive')
      end

      before do
        sign_in email_user
      end

      it 'redirects to subscription page (no trial for email users)' do
        visit dashboard_path
        expect(page).to have_current_path(new_subscription_path)
      end

      it 'does not qualify for QBO SSO trial' do
        expect(inactive_subscription.reload.qbo_sso_free_trial?).to be false
        expect(email_user.reload.has_active_subscription?).to be false
      end
    end

    context 'with paid subscription' do
      let!(:paid_subscription) do
        create(:subscription, user: email_user, status: 'paid')
      end

      before do
        sign_in email_user
      end

      it 'can access dashboard' do
        visit dashboard_path
        expect(page).to have_current_path(dashboard_path)
        expect(email_user.reload.has_active_subscription?).to be true
      end
    end
  end

  describe 'Subscription cancellation during trial' do
    let(:qbo_user) do
      create(:user,
        email: 'qbo_cancel@example.com',
        qbo_sub_id: 'qbo_sub_cancel_123',
        confirmed_at: Time.current,
        without_subscription: true
      )
    end

    let!(:trial_subscription) do
      create(:subscription, user: qbo_user, status: 'inactive')
    end

    before do
      sign_in qbo_user
    end

    it 'allows cancellation of trial subscription' do
      # Trial subscriptions can be "canceled" (though there's no Stripe sub to cancel)
      expect(trial_subscription.active_or_trial?).to be true

      trial_subscription.update!(status: 'canceled')

      expect(trial_subscription.reload.active_or_trial?).to be false
      expect(qbo_user.reload.has_active_subscription?).to be false
    end
  end

  describe 'Trial to paid conversion via Stripe' do
    let(:qbo_user) do
      create(:user,
        email: 'qbo_convert@example.com',
        qbo_sub_id: 'qbo_sub_convert_123',
        confirmed_at: Time.current,
        stripe_customer_id: 'cus_test_123',
        without_subscription: true
      )
    end

    let!(:trial_subscription) do
      create(:subscription, user: qbo_user, status: 'inactive', created_at: 5.days.ago)
    end

    it 'preserves subscription record when converting to paid' do
      original_subscription_id = trial_subscription.id
      original_created_at = trial_subscription.created_at

      # Simulate Stripe webhook updating subscription
      trial_subscription.update!(
        status: 'paid',
        stripe_subscription_id: 'sub_converted_123',
        current_period_start: Time.current,
        current_period_end: 30.days.from_now
      )

      trial_subscription.reload

      # Same subscription record, updated status
      expect(trial_subscription.id).to eq(original_subscription_id)
      expect(trial_subscription.created_at).to eq(original_created_at)  # Preserved
      expect(trial_subscription.status).to eq('paid')
      expect(trial_subscription.stripe_subscription_id).to eq('sub_converted_123')
      expect(trial_subscription.active_or_trial?).to be true
      expect(trial_subscription.active?).to be true
    end
  end

  describe 'Edge cases' do
    context 'QBO SSO user without subscription record' do
      let(:qbo_user_no_sub) do
        create(:user,
          email: 'qbo_nosub@example.com',
          qbo_sub_id: 'qbo_sub_nosub_123',
          confirmed_at: Time.current,
          without_subscription: true
        )
      end

      before do
        sign_in qbo_user_no_sub
      end

      it 'redirects to subscription page' do
        visit dashboard_path
        expect(page).to have_current_path(new_subscription_path)
        expect(qbo_user_no_sub.reload.has_active_subscription?).to be false
      end
    end

    context 'existing email user links QBO SSO' do
      let(:existing_user) do
        create(:user,
          email: 'existing@example.com',
          qbo_sub_id: nil,
          confirmed_at: Time.current,
          without_subscription: true
        )
      end

      let!(:paid_subscription) do
        create(:subscription, user: existing_user, status: 'paid')
      end

      before do
        sign_in existing_user
        # Simulate linking QBO SSO to existing account
        existing_user.update!(qbo_sub_id: 'qbo_sub_linked_123')
      end

      it 'maintains paid subscription (does not convert to trial)' do
        expect(existing_user.reload.has_active_subscription?).to be true
        expect(paid_subscription.reload.status).to eq('paid')
        expect(paid_subscription.active?).to be true
        # Note: qbo_sso_free_trial? will be false because status is 'paid', not 'inactive'
      end

      it 'can still access dashboard' do
        visit dashboard_path
        expect(page).to have_current_path(dashboard_path)
      end
    end
  end
end
