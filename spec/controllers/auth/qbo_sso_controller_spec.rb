require 'rails_helper'

RSpec.describe Auth::QboSsoController, type: :controller do
  render_views

  before do
    ENV['QBO_CLIENT_ID'] = 'test_client_id'
    ENV['QBO_CLIENT_SECRET'] = 'test_client_secret'

    # Stub Intuit OpenID discovery document request (SDK makes this on initialization)
    stub_request(:get, "https://developer.intuit.com/.well-known/openid_sandbox_configuration/")
      .to_return(
        status: 200,
        body: {
          authorization_endpoint: "https://appcenter.intuit.com/connect/oauth2",
          token_endpoint: "https://oauth.platform.intuit.com/oauth2/v1/tokens/bearer",
          revocation_endpoint: "https://developer.api.intuit.com/v2/oauth2/tokens/revoke",
          userinfo_endpoint: "https://accounts.platform.intuit.com/v1/openid_connect/userinfo",
          issuer: "https://oauth.platform.intuit.com/op/v1",
          jwks_uri: "https://oauth.platform.intuit.com/op/v1/jwks"
        }.to_json,
        headers: { 'Content-Type' => 'application/json' }
      )
  end

  # Helper to create SDK OAuth errors
  def create_oauth_error(code: 400, body: 'error', intuit_tid: 'test-tid-123')
    response = double('HTTPResponse',
      code: code,
      body: body,
      headers: { 'intuit_tid' => intuit_tid, 'date' => Time.current.to_s }
    )
    IntuitOAuth::OAuth2ClientException.new(response)
  end

  describe 'GET #connect' do
    it 'redirects to QBO authorization URL with OpenID scopes for SSO' do
      get :connect

      expect(response).to redirect_to(/appcenter/)
      expect(response.location).to include('client_id=test_client_id')
      expect(response.location).to include('scope=com.intuit.quickbooks.accounting')
      expect(response.location).to include('openid')
      expect(response.location).to include('profile')
      expect(response.location).to include('email')
    end

    it 'disables caching per Intuit security requirements (inherited from ApplicationController)' do
      get :connect

      # Verify OAuth flow pages don't cache sensitive data
      expect(response.headers['Cache-Control']).to include('no-store')
      expect(response.headers['Pragma']).to eq('no-cache')
      expect(response.headers['Expires']).to eq('0')
    end

    it 'stores state parameter in session for CSRF protection' do
      get :connect

      expect(session[:qbo_sso_state]).to be_present
      expect(session[:qbo_sso_state].length).to eq(64) # hex(32) = 64 chars
    end

    it 'includes state parameter in authorization URL' do
      get :connect

      expect(response.location).to include("state=#{session[:qbo_sso_state]}")
    end

    it 'uses SSO callback URL in authorization request' do
      get :connect
      expect(response.location).to include('appcenter.intuit.com')
    end
  end

  describe 'GET #callback' do
    it 'stores OAuth parameters in session with string keys' do
      get :callback, params: { code: 'auth_code_123', realmId: 'realm_123', state: 'test_state_123' }

      expect(session[:qbo_sso_callback_params]).to be_present
      expect(session[:qbo_sso_callback_params]['code']).to eq('auth_code_123')
      expect(session[:qbo_sso_callback_params]['state']).to eq('test_state_123')
      expect(session[:qbo_sso_callback_params]['realm_id']).to eq('realm_123')
    end

    it 'issues 302 redirect to process endpoint' do
      get :callback, params: { code: 'auth_code_123', realmId: 'realm_123', state: 'test_state_123' }

      expect(response).to redirect_to(auth_qbo_sso_complete_path)
      expect(response.status).to eq(302)
    end

    it 'does not process OAuth flow in callback (security: prevents token leakage via Referer)' do
      # Should NOT exchange code for tokens in callback
      expect(controller).not_to receive(:exchange_code_for_tokens)
      expect(QboService).not_to receive(:validate_id_token)
      expect(QboService).not_to receive(:fetch_user_info)

      get :callback, params: { code: 'auth_code_123', realmId: 'realm_123', state: 'test_state_123' }
    end
  end

  describe 'GET #complete' do
    let(:valid_token_response) do
      {
        access_token: 'qbo_access_token_123',
        refresh_token: 'qbo_refresh_token_123',
        expires_in: 3600,
        id_token: 'qbo_id_token_123'
      }
    end

    let(:valid_user_info) do
      {
        sub: 'qbo_user_sub_123',
        email: 'newuser@example.com',
        email_verified: true,
        given_name: 'John',
        family_name: 'Doe'
      }
    end

    before do
      # Set session state for OAuth validation
      session[:qbo_sso_state] = 'test_state_123'
      # Simulate callback having stored params in session with string keys
      session[:qbo_sso_callback_params] = {
        'code' => 'auth_code_123',
        'state' => 'test_state_123',
        'realm_id' => 'realm_123'
      }
    end

    context 'with missing session params (session expired or tampered)' do
      it 'redirects to login with error when no callback params in session' do
        session.delete(:qbo_sso_callback_params)

        get :complete

        expect(response).to redirect_to(new_user_session_path)
        expect(flash[:alert]).to eq('Authentication session expired. Please try again.')
      end
    end

    context 'with verified email for new user' do
      it 'creates new user and signs them in' do
        allow(controller).to receive(:exchange_code_for_tokens).and_return(valid_token_response)
        allow(QboService).to receive(:validate_id_token).and_return(true)
        allow(QboService).to receive(:fetch_user_info).and_return(valid_user_info)

        expect {
          get :complete
        }.to change(User, :count).by(1)

        user = User.last
        expect(user.email).to eq('newuser@example.com')
        expect(user.qbo_sub_id).to eq('qbo_user_sub_123')
        expect(user.qbo_realm_id).to eq('realm_123')
        expect(user.qbo_user_email_verified).to be true
        expect(user.confirmed_at).to be_present # Auto-confirmed
        expect(user.qbo_connected_at).to be_present

        expect(controller.current_user).to eq(user)
        expect(response).to redirect_to(dashboard_path)
        expect(flash[:notice]).to eq('Successfully signed in with QuickBooks!')
      end

      it 'stores OAuth tokens for new user' do
        allow(controller).to receive(:exchange_code_for_tokens).and_return(valid_token_response)
        allow(QboService).to receive(:validate_id_token).and_return(true)
        allow(QboService).to receive(:fetch_user_info).and_return(valid_user_info)

        get :complete

        user = User.last
        expect(user.qbo_access_token).to eq('qbo_access_token_123')
        expect(user.qbo_refresh_token).to eq('qbo_refresh_token_123')
        expect(user.qbo_id_token).to eq('qbo_id_token_123')
        expect(user.qbo_token_expires_at).to be_present
      end

      it 'stores OpenID profile information for new user' do
        allow(controller).to receive(:exchange_code_for_tokens).and_return(valid_token_response)
        allow(QboService).to receive(:validate_id_token).and_return(true)
        allow(QboService).to receive(:fetch_user_info).and_return(valid_user_info)

        get :complete

        user = User.last
        expect(user.qbo_user_email).to eq('newuser@example.com')
        expect(user.qbo_user_email_verified).to be true
        expect(user.qbo_user_given_name).to eq('John')
        expect(user.qbo_user_family_name).to eq('Doe')
        expect(user.first_name).to eq('John')
        expect(user.last_name).to eq('Doe')
      end

      it 'creates audit log for SSO signup' do
        allow(controller).to receive(:exchange_code_for_tokens).and_return(valid_token_response)
        allow(QboService).to receive(:validate_id_token).and_return(true)
        allow(QboService).to receive(:fetch_user_info).and_return(valid_user_info)

        expect {
          get :complete
        }.to change(AuditLog, :count).by(1)

        audit_log = AuditLog.last
        expect(audit_log.action).to eq('qbo_sso_signup')
        expect(audit_log.metadata['signup_method']).to eq('qbo_sso')
      end

      it 'creates trial subscription for new QBO SSO user' do
        allow(controller).to receive(:exchange_code_for_tokens).and_return(valid_token_response)
        allow(QboService).to receive(:validate_id_token).and_return(true)
        allow(QboService).to receive(:fetch_user_info).and_return(valid_user_info)

        expect {
          get :complete
        }.to change(Subscription, :count).by(1)

        user = User.last
        subscription = user.subscription

        expect(subscription).to be_present
        expect(subscription.status).to eq('inactive')
        expect(subscription.qbo_sso_free_trial?).to be true
        expect(subscription.active_or_trial?).to be true
      end

      it 'allows new QBO SSO user to access dashboard with trial subscription' do
        allow(controller).to receive(:exchange_code_for_tokens).and_return(valid_token_response)
        allow(QboService).to receive(:validate_id_token).and_return(true)
        allow(QboService).to receive(:fetch_user_info).and_return(valid_user_info)

        get :complete

        user = User.last
        expect(user.has_active_subscription?).to be true
      end
    end

    context 'with verified email for existing QBO SSO user' do
      let!(:existing_user) do
        create(:user,
          email: 'existing@example.com',
          qbo_sub_id: 'qbo_user_sub_123',
          qbo_realm_id: 'old_realm',
          qbo_access_token: 'old_token'
        )
      end

      it 'finds existing user by QBO sub ID and updates tokens' do
        # Override session to test with new realm ID
        session[:qbo_sso_callback_params]['realm_id'] = 'new_realm'

        allow(controller).to receive(:exchange_code_for_tokens).and_return(valid_token_response)
        allow(QboService).to receive(:validate_id_token).and_return(true)
        allow(QboService).to receive(:fetch_user_info).and_return(
          valid_user_info.merge(email: 'existing@example.com')
        )

        expect {
          get :complete
        }.not_to change(User, :count)

        existing_user.reload
        expect(existing_user.qbo_realm_id).to eq('new_realm')
        expect(existing_user.qbo_access_token).to eq('qbo_access_token_123')
        expect(existing_user.qbo_refresh_token).to eq('qbo_refresh_token_123')

        expect(controller.current_user).to eq(existing_user)
        expect(response).to redirect_to(dashboard_path)
      end
    end

    context 'with verified email for existing email/password user' do
      let!(:existing_user) do
        create(:user,
          email: 'newuser@example.com',
          qbo_sub_id: nil # No QBO SSO yet
        )
      end

      it 'links QBO SSO to existing account' do
        allow(controller).to receive(:exchange_code_for_tokens).and_return(valid_token_response)
        allow(QboService).to receive(:validate_id_token).and_return(true)
        allow(QboService).to receive(:fetch_user_info).and_return(valid_user_info)

        expect {
          get :complete
        }.not_to change(User, :count)

        existing_user.reload
        expect(existing_user.qbo_sub_id).to eq('qbo_user_sub_123')
        expect(existing_user.qbo_realm_id).to eq('realm_123')
        expect(existing_user.qbo_access_token).to eq('qbo_access_token_123')

        expect(controller.current_user).to eq(existing_user)
        expect(response).to redirect_to(dashboard_path)
      end
    end

    context 'with unverified email (CRITICAL INTUIT REQUIREMENT)' do
      it 'renders email_not_verified page and does not create user' do
        allow(controller).to receive(:exchange_code_for_tokens).and_return(valid_token_response)
        allow(QboService).to receive(:validate_id_token).and_return(true)
        allow(QboService).to receive(:fetch_user_info).and_return(
          valid_user_info.merge(email_verified: false)
        )

        expect {
          get :complete
        }.not_to change(User, :count)

        expect(response).to have_http_status(:forbidden)
        expect(response.body).to include('Email Verification Required')
        expect(response.body).to include('https://accounts.intuit.com/app/account-manager/security')
      end

      it 'does not sign in user when email is unverified' do
        allow(controller).to receive(:exchange_code_for_tokens).and_return(valid_token_response)
        allow(QboService).to receive(:validate_id_token).and_return(true)
        allow(QboService).to receive(:fetch_user_info).and_return(
          valid_user_info.merge(email_verified: false)
        )

        get :complete

        expect(controller.current_user).to be_nil
      end

      it 'logs warning when email is not verified' do
        allow(controller).to receive(:exchange_code_for_tokens).and_return(valid_token_response)
        allow(QboService).to receive(:validate_id_token).and_return(true)
        allow(QboService).to receive(:fetch_user_info).and_return(
          valid_user_info.merge(email_verified: false)
        )

        expect(Rails.logger).to receive(:warn).with(/Email not verified/)

        get :complete
      end
    end

    context 'with CSRF protection (state parameter)' do
      it 'rejects complete with missing state parameter in session' do
        session[:qbo_sso_callback_params]['state'] = nil
        allow(controller).to receive(:exchange_code_for_tokens).and_return(valid_token_response)

        get :complete

        expect(response).to redirect_to(new_user_session_path)
        expect(flash[:alert]).to eq('Authentication failed. Please try again.')
      end

      it 'rejects complete with mismatched state parameter' do
        session[:qbo_sso_callback_params]['state'] = 'wrong_state'
        allow(controller).to receive(:exchange_code_for_tokens).and_return(valid_token_response)

        get :complete

        expect(response).to redirect_to(new_user_session_path)
        expect(flash[:alert]).to eq('Authentication failed. Please try again.')
      end

      it 'clears state from session after successful validation' do
        allow(controller).to receive(:exchange_code_for_tokens).and_return(valid_token_response)
        allow(QboService).to receive(:validate_id_token).and_return(true)
        allow(QboService).to receive(:fetch_user_info).and_return(valid_user_info)

        get :complete

        expect(session[:qbo_sso_state]).to be_nil
      end

      it 'clears callback params from session after processing' do
        allow(controller).to receive(:exchange_code_for_tokens).and_return(valid_token_response)
        allow(QboService).to receive(:validate_id_token).and_return(true)
        allow(QboService).to receive(:fetch_user_info).and_return(valid_user_info)

        get :complete

        expect(session[:qbo_sso_callback_params]).to be_nil
      end
    end

    context 'with ID token validation' do
      it 'rejects complete when ID token validation fails' do
        allow(controller).to receive(:exchange_code_for_tokens).and_return(valid_token_response)
        allow(QboService).to receive(:validate_id_token).and_return(false)

        expect {
          get :complete
        }.not_to change(User, :count)

        expect(response).to redirect_to(new_user_session_path)
        expect(flash[:alert]).to eq('Failed to validate QuickBooks identity. Please try again.')
      end
    end

    context 'with user info fetch failure' do
      it 'rejects complete when user info is nil' do
        allow(controller).to receive(:exchange_code_for_tokens).and_return(valid_token_response)
        allow(QboService).to receive(:validate_id_token).and_return(true)
        allow(QboService).to receive(:fetch_user_info).and_return(nil)

        expect {
          get :complete
        }.not_to change(User, :count)

        expect(response).to redirect_to(new_user_session_path)
        expect(flash[:alert]).to eq('Failed to retrieve user information from QuickBooks. Please try again.')
      end
    end

    context 'with OAuth errors' do
      it 'handles SDK OAuth2ClientException' do
        oauth_error = create_oauth_error(body: 'invalid_grant', intuit_tid: 'test-tid-123')
        allow(controller).to receive(:exchange_code_for_tokens).and_raise(oauth_error)

        expect {
          get :complete
        }.not_to change(User, :count)

        expect(response).to redirect_to(new_user_session_path)
        expect(flash[:alert]).to eq('Failed to authenticate with QuickBooks. Please try again.')
      end

      it 'handles general exceptions' do
        allow(controller).to receive(:exchange_code_for_tokens).and_raise(StandardError, 'Network error')

        expect {
          get :complete
        }.not_to change(User, :count)

        expect(response).to redirect_to(new_user_session_path)
        expect(flash[:alert]).to eq('Authentication failed. Please try again.')
      end
    end

    context 'with user creation failure' do
      it 'handles validation errors during user creation' do
        allow(controller).to receive(:exchange_code_for_tokens).and_return(valid_token_response)
        allow(QboService).to receive(:validate_id_token).and_return(true)
        allow(QboService).to receive(:fetch_user_info).and_return(valid_user_info)

        # Mock user creation to fail
        allow(QboSsoService).to receive(:find_or_create_user).and_return(
          User.new.tap { |u| u.errors.add(:base, 'Email already taken') }
        )

        expect {
          get :complete
        }.not_to change(User, :count)

        expect(response).to redirect_to(new_user_session_path)
        expect(flash[:alert]).to include('Failed to create account')
      end
    end
  end
end
