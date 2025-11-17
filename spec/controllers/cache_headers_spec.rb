require 'rails_helper'

# Comprehensive test suite for cache-control headers
# Required by Intuit security requirements for QBO integration
#
# Security Requirement:
# "Caching is disabled on all SSL pages and all pages that contain sensitive data
# by using value no-cache and no-store instead of private in the Cache-Control header."

RSpec.describe 'Cache-Control Headers (Intuit Security Requirement)', type: :controller do
  let(:user) { create(:user) }
  let!(:subscription) { create(:subscription, user: user, status: 'paid') }

  shared_examples 'applies security cache headers' do
    it 'disables caching per Intuit security requirements' do
      make_request

      # Intuit Requirement: "Caching is disabled on all SSL pages and all pages
      # that contain sensitive data by using value no-cache and no-store"
      #
      # Verify that caching is disabled (no-store prevents ALL caching)
      cache_control = response.headers['Cache-Control']
      expect(cache_control).to be_present, "Cache-Control header must be set"
      expect(cache_control).to include('no-store'), "Cache-Control must include 'no-store' to prevent caching"

      # HTTP/1.0 compatibility headers
      expect(response.headers['Pragma']).to eq('no-cache'), "Pragma header required for HTTP/1.0 compatibility"
      expect(response.headers['Expires']).to eq('0'), "Expires header required to prevent caching"
    end
  end

  describe 'ApplicationController' do
    controller(ApplicationController) do
      def index
        render plain: 'test'
      end
    end

    before do
      routes.draw { get 'index' => 'anonymous#index' }
      sign_in user
    end

    it_behaves_like 'applies security cache headers' do
      let(:make_request) { get :index }
    end
  end

  describe 'Devise Controllers (via inheritance)' do
    describe Users::SessionsController do
      before do
        @request.env["devise.mapping"] = Devise.mappings[:user]
      end

      it_behaves_like 'applies security cache headers' do
        let(:make_request) { get :new }
      end
    end

    describe Users::RegistrationsController do
      before do
        @request.env["devise.mapping"] = Devise.mappings[:user]

        # Stub Stripe API calls
        allow(Stripe::Customer).to receive(:create).and_return(double(id: 'cus_test123'))
        allow(Stripe::Checkout::Session).to receive(:create).and_return(
          double(url: 'https://checkout.stripe.com/test')
        )
      end

      it_behaves_like 'applies security cache headers' do
        let(:make_request) { get :new }
      end

      context 'on signup form POST' do
        it_behaves_like 'applies security cache headers' do
          let(:make_request) do
            post :create, params: {
              user: {
                email: "test-#{SecureRandom.hex(4)}@example.com",
                password: 'password123',
                password_confirmation: 'password123',
                first_name: 'Test',
                last_name: 'User',
                timezone: 'UTC'
              }
            }
          end
        end
      end
    end

    describe Users::PasswordsController do
      before do
        @request.env["devise.mapping"] = Devise.mappings[:user]
      end

      it_behaves_like 'applies security cache headers' do
        let(:make_request) { get :new }
      end
    end

    describe Users::ConfirmationsController do
      before do
        @request.env["devise.mapping"] = Devise.mappings[:user]
      end

      it_behaves_like 'applies security cache headers' do
        let(:make_request) { get :new }
      end
    end
  end

  describe 'OAuth Controllers (contain OAuth tokens)' do
    describe Auth::QboSsoController do
      before do
        ENV['QBO_CLIENT_ID'] = 'test_client_id'
        ENV['QBO_CLIENT_SECRET'] = 'test_client_secret'

        # Stub Intuit OpenID discovery document
        stub_request(:get, "https://developer.intuit.com/.well-known/openid_sandbox_configuration/")
          .to_return(
            status: 200,
            body: {
              authorization_endpoint: "https://appcenter.intuit.com/connect/oauth2",
              token_endpoint: "https://oauth.platform.intuit.com/oauth2/v1/tokens/bearer",
              userinfo_endpoint: "https://accounts.platform.intuit.com/v1/openid_connect/userinfo",
              issuer: "https://oauth.platform.intuit.com/op/v1"
            }.to_json,
            headers: { 'Content-Type' => 'application/json' }
          )
      end

      it_behaves_like 'applies security cache headers' do
        let(:make_request) { get :connect }
      end
    end

    describe Auth::QboController do
      before do
        ENV['QBO_CLIENT_ID'] = 'test_client_id'
        ENV['QBO_CLIENT_SECRET'] = 'test_client_secret'
        sign_in user

        # Stub Intuit OpenID discovery document
        stub_request(:get, "https://developer.intuit.com/.well-known/openid_sandbox_configuration/")
          .to_return(
            status: 200,
            body: {
              authorization_endpoint: "https://appcenter.intuit.com/connect/oauth2",
              token_endpoint: "https://oauth.platform.intuit.com/oauth2/v1/tokens/bearer"
            }.to_json,
            headers: { 'Content-Type' => 'application/json' }
          )
      end

      it_behaves_like 'applies security cache headers' do
        let(:make_request) { get :connect }
      end
    end

    describe Auth::FreelancerController do
      before do
        ENV['FREELANCER_ENVIRONMENT'] = 'sandbox'
        ENV['FREELANCER_CLIENT_ID'] = 'test_client_id'
        ENV['FREELANCER_CLIENT_SECRET'] = 'test_client_secret'
        sign_in user
      end

      it_behaves_like 'applies security cache headers' do
        let(:make_request) { get :connect }
      end
    end
  end

  describe 'Authenticated Pages (contain sensitive user data)' do
    controller(ApplicationController) do
      def dashboard
        render plain: 'dashboard'
      end
    end

    before do
      routes.draw { get 'dashboard' => 'anonymous#dashboard' }
      sign_in user
    end

    it_behaves_like 'applies security cache headers' do
      let(:make_request) { get :dashboard }
    end
  end
end
