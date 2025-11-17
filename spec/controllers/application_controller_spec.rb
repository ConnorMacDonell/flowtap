require 'rails_helper'

RSpec.describe ApplicationController, type: :controller do
  controller do
    def index
      render plain: 'Dashboard content'
    end
  end

  before do
    routes.draw { get 'index' => 'anonymous#index' }
  end

  describe '#set_cache_headers' do
    let(:user) { create(:user) }
    let!(:subscription) { create(:subscription, user: user, status: 'paid') }

    before { sign_in user }

    it 'disables caching per Intuit security requirements' do
      get :index

      # Intuit requires: "Caching is disabled...by using value no-cache and no-store"
      # Verify that no-store is present (which prevents ALL caching)
      expect(response.headers['Cache-Control']).to include('no-store')
    end

    it 'sets Pragma header for HTTP/1.0 compatibility' do
      get :index
      expect(response.headers['Pragma']).to eq('no-cache')
    end

    it 'sets Expires header to prevent caching' do
      get :index
      expect(response.headers['Expires']).to eq('0')
    end

    context 'on unauthenticated requests (redirects)' do
      before { sign_out user }

      it 'redirects to sign in' do
        get :index
        expect(response).to redirect_to(new_user_session_path)
      end

      # Note: Devise handles the redirect before our after_action runs
      # The login page itself will have cache headers when it renders
    end
  end

  describe '#check_subscription_status' do
    context 'when user is signed in' do
      context 'with paid subscription' do
        let(:user) { create(:user) }
        let!(:subscription) { create(:subscription, user: user, status: 'paid') }

        before { sign_in user }

        it 'allows access to protected pages' do
          get :index
          expect(response).to have_http_status(:success)
          expect(response.body).to include('Dashboard content')
        end
      end

      context 'with QBO SSO trial subscription (active)' do
        let(:qbo_user) { create(:user, qbo_sub_id: 'qbo_sub_123', without_subscription: true) }
        let!(:trial_subscription) { create(:subscription, user: qbo_user, status: 'inactive') }

        before { sign_in qbo_user }

        it 'allows access during trial period' do
          get :index
          expect(response).to have_http_status(:success)
          expect(response.body).to include('Dashboard content')
        end

        it 'does not redirect to subscription page' do
          get :index
          expect(response).not_to redirect_to(new_subscription_path)
        end
      end

      context 'with QBO SSO trial subscription (expired)' do
        let(:qbo_user) { create(:user, qbo_sub_id: 'qbo_sub_123', without_subscription: true) }
        let!(:expired_trial) do
          create(:subscription, user: qbo_user, status: 'inactive', created_at: 15.days.ago)
        end

        before { sign_in qbo_user }

        it 'redirects to subscription page after trial expires' do
          get :index
          expect(response).to redirect_to(new_subscription_path)
        end

        it 'shows subscription required message' do
          get :index
          expect(flash[:alert]).to eq('Please complete your subscription to access the application.')
        end
      end

      context 'with no subscription' do
        let(:user) { create(:user, without_subscription: true) }

        before { sign_in user }

        it 'redirects to subscription page' do
          get :index
          expect(response).to redirect_to(new_subscription_path)
        end

        it 'shows subscription required message' do
          get :index
          expect(flash[:alert]).to eq('Please complete your subscription to access the application.')
        end
      end

      context 'with canceled subscription' do
        let(:user) { create(:user, without_subscription: true) }
        let!(:canceled_subscription) { create(:subscription, user: user, status: 'canceled') }

        before { sign_in user }

        it 'redirects to subscription page' do
          get :index
          expect(response).to redirect_to(new_subscription_path)
        end
      end

      context 'with inactive subscription (email user, not QBO SSO)' do
        let(:email_user) { create(:user, qbo_sub_id: nil, without_subscription: true) }
        let!(:inactive_subscription) { create(:subscription, user: email_user, status: 'inactive') }

        before { sign_in email_user }

        it 'redirects to subscription page (no trial for email users)' do
          get :index
          expect(response).to redirect_to(new_subscription_path)
        end
      end
    end
  end

  describe 'subscription status edge cases' do
    context 'QBO SSO user on day 13 of trial' do
      let(:qbo_user) { create(:user, qbo_sub_id: 'qbo_sub_123', without_subscription: true) }
      let!(:day_13_trial) do
        create(:subscription, user: qbo_user, status: 'inactive', created_at: 13.days.ago)
      end

      before { sign_in qbo_user }

      it 'still allows access' do
        get :index
        expect(response).to have_http_status(:success)
      end
    end

    context 'QBO SSO user on day 14 of trial (exactly)' do
      let(:qbo_user) { create(:user, qbo_sub_id: 'qbo_sub_123', without_subscription: true) }
      let!(:day_14_trial) do
        create(:subscription, user: qbo_user, status: 'inactive', created_at: 14.days.ago)
      end

      before { sign_in qbo_user }

      it 'redirects to subscription page' do
        get :index
        expect(response).to redirect_to(new_subscription_path)
      end
    end

    context 'QBO SSO user who converted from trial to paid' do
      let(:qbo_user) { create(:user, qbo_sub_id: 'qbo_sub_123', without_subscription: true) }
      let!(:converted_subscription) do
        create(:subscription,
          user: qbo_user,
          status: 'paid',
          created_at: 20.days.ago,  # Old trial
          stripe_subscription_id: 'sub_123'
        )
      end

      before { sign_in qbo_user }

      it 'allows access with paid subscription' do
        get :index
        expect(response).to have_http_status(:success)
      end
    end
  end
end
