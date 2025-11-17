require 'rails_helper'

RSpec.describe Auth::QboController, type: :controller do
  let(:user) { create(:user) }

  before do
    sign_in user
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
    it 'redirects to QBO authorization URL with OpenID scopes' do
      get :connect

      expect(response).to redirect_to(/appcenter/)
      expect(response.location).to include('client_id=test_client_id')
      expect(response.location).to include('scope=com.intuit.quickbooks.accounting')
      expect(response.location).to include('openid')
      expect(response.location).to include('profile')
      expect(response.location).to include('email')
    end

    it 'uses standard authorization URL' do
      get :connect
      expect(response.location).to include('appcenter.intuit.com')
    end

    context 'when user is not authenticated' do
      before { sign_out user }

      it 'redirects to sign in page' do
        get :connect
        expect(response).to redirect_to(new_user_session_path)
      end
    end
  end

  describe 'GET #callback' do
    it 'stores OAuth parameters in session' do
      get :callback, params: { code: 'auth_code_123', realmId: 'realm_123', state: 'test_state_123' }

      expect(session[:qbo_callback_params]).to be_present
      expect(session[:qbo_callback_params][:code]).to eq('auth_code_123')
      expect(session[:qbo_callback_params][:state]).to eq('test_state_123')
      expect(session[:qbo_callback_params][:realm_id]).to eq('realm_123')
    end

    it 'issues 302 redirect to process endpoint' do
      get :callback, params: { code: 'auth_code_123', realmId: 'realm_123', state: 'test_state_123' }

      expect(response).to redirect_to(auth_qbo_complete_path)
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
    before do
      # Set session state for OAuth validation
      session[:qbo_oauth_state] = 'test_state_123'
      # Simulate callback having stored params in session
      session[:qbo_callback_params] = {
        code: 'auth_code_123',
        state: 'test_state_123',
        realm_id: 'realm_123'
      }
    end

    it 'redirects with error when no callback params in session' do
      session.delete(:qbo_callback_params)

      get :complete

      expect(response).to redirect_to(dashboard_path)
      expect(flash[:alert]).to eq('Authentication session expired. Please try again.')
    end

    it 'handles successful token exchange' do
      # Mock the controller's private method directly - SDK returns symbol keys
      allow(controller).to receive(:exchange_code_for_tokens).and_return({
        access_token: 'qbo_access_token_123',
        refresh_token: 'qbo_refresh_token_123',
        expires_in: 3600,
        id_token: 'qbo_id_token_123'
      })

      # Mock OpenID Connect validation and user info retrieval
      allow(QboService).to receive(:validate_id_token).and_return(true)
      allow(QboService).to receive(:fetch_user_info).and_return({
        sub: 'qbo_user_sub_123',
        email: 'user@example.com',
        email_verified: true,
        given_name: 'John',
        family_name: 'Doe'
      })

      original_time = Time.current
      allow(Time).to receive(:current).and_return(original_time)

      get :complete

      user.reload
      expect(user.qbo_realm_id).to eq('realm_123')
      expect(user.qbo_access_token).to eq('qbo_access_token_123')
      expect(user.qbo_refresh_token).to eq('qbo_refresh_token_123')
      expect(user.qbo_token_expires_at).to be_within(1.second).of(original_time + 3600.seconds)
      expect(user.qbo_connected_at).to be_within(1.second).of(original_time)
      expect(user.qbo_id_token).to eq('qbo_id_token_123')
      expect(user.qbo_sub_id).to eq('qbo_user_sub_123')
      expect(user.qbo_user_email).to eq('user@example.com')
      expect(user.qbo_user_email_verified).to be true
      expect(user.qbo_user_given_name).to eq('John')
      expect(user.qbo_user_family_name).to eq('Doe')

      expect(response).to redirect_to(dashboard_path)
      expect(flash[:notice]).to eq('QuickBooks Online connected successfully!')
    end

    it 'handles SDK OAuth errors' do
      # Mock SDK-specific OAuth error
      oauth_error = create_oauth_error(body: 'invalid_grant', intuit_tid: 'test-tid-123')
      allow(controller).to receive(:exchange_code_for_tokens).and_raise(oauth_error)

      get :complete

      user.reload
      expect(user.qbo_realm_id).to be_nil

      expect(response).to redirect_to(dashboard_path)
      expect(flash[:alert]).to eq('Failed to connect to QuickBooks Online. Please try again.')
    end

    it 'handles general token exchange failures' do
      allow(controller).to receive(:exchange_code_for_tokens).and_raise(StandardError, 'Token exchange failed')

      get :complete

      user.reload
      expect(user.qbo_realm_id).to be_nil

      expect(response).to redirect_to(dashboard_path)
      expect(flash[:alert]).to eq('Failed to connect to QuickBooks Online. Please try again.')
    end

    it 'rejects connection when ID token validation fails' do
      allow(controller).to receive(:exchange_code_for_tokens).and_return({
        access_token: 'qbo_access_token_123',
        refresh_token: 'qbo_refresh_token_123',
        expires_in: 3600,
        id_token: 'invalid_id_token'
      })

      # Mock ID token validation to fail
      allow(QboService).to receive(:validate_id_token).and_return(false)

      get :complete

      user.reload
      expect(user.qbo_realm_id).to be_nil
      expect(user.qbo_id_token).to be_nil

      expect(response).to redirect_to(dashboard_path)
      expect(flash[:alert]).to eq('Failed to validate QuickBooks identity. Please try again.')
    end

    it 'rejects connection when user info fetch fails' do
      allow(controller).to receive(:exchange_code_for_tokens).and_return({
        access_token: 'qbo_access_token_123',
        refresh_token: 'qbo_refresh_token_123',
        expires_in: 3600,
        id_token: 'qbo_id_token_123'
      })

      allow(QboService).to receive(:validate_id_token).and_return(true)
      allow(QboService).to receive(:fetch_user_info).and_return(nil)

      get :complete

      user.reload
      expect(user.qbo_realm_id).to be_nil
      expect(user.qbo_user_email).to be_nil

      expect(response).to redirect_to(dashboard_path)
      expect(flash[:alert]).to eq('Failed to retrieve user information from QuickBooks. Please try again.')
    end

    it 'rejects connection when email is not verified' do
      allow(controller).to receive(:exchange_code_for_tokens).and_return({
        access_token: 'qbo_access_token_123',
        refresh_token: 'qbo_refresh_token_123',
        expires_in: 3600,
        id_token: 'qbo_id_token_123'
      })

      allow(QboService).to receive(:validate_id_token).and_return(true)
      allow(QboService).to receive(:fetch_user_info).and_return({
        sub: 'qbo_user_sub_123',
        email: 'user@example.com',
        email_verified: false,
        given_name: 'John',
        family_name: 'Doe'
      })

      get :complete

      user.reload
      expect(user.qbo_realm_id).to be_nil
      expect(user.qbo_user_email).to be_nil
      expect(user.qbo_user_email_verified).to be_nil

      expect(response).to redirect_to(dashboard_path)
      expect(flash[:alert]).to eq('Your QuickBooks email is not verified. Please verify your email with Intuit and try again.')
    end

    it 'rejects complete with missing state parameter in session' do
      session[:qbo_callback_params][:state] = nil

      get :complete

      expect(response).to redirect_to(dashboard_path)
      expect(flash[:alert]).to eq('OAuth state validation failed. Please try connecting again.')
    end

    it 'rejects complete with mismatched state parameter' do
      session[:qbo_callback_params][:state] = 'wrong_state'

      get :complete

      expect(response).to redirect_to(dashboard_path)
      expect(flash[:alert]).to eq('OAuth state validation failed. Please try connecting again.')
    end

    it 'clears state from session after successful connection' do
      allow(controller).to receive(:exchange_code_for_tokens).and_return({
        access_token: 'qbo_access_token_123',
        refresh_token: 'qbo_refresh_token_123',
        expires_in: 3600,
        id_token: 'qbo_id_token_123'
      })

      allow(QboService).to receive(:validate_id_token).and_return(true)
      allow(QboService).to receive(:fetch_user_info).and_return({
        sub: 'qbo_user_sub_123',
        email: 'user@example.com',
        email_verified: true,
        given_name: 'John',
        family_name: 'Doe'
      })

      get :complete

      expect(session[:qbo_oauth_state]).to be_nil
    end

    it 'clears callback params from session after processing' do
      allow(controller).to receive(:exchange_code_for_tokens).and_return({
        access_token: 'qbo_access_token_123',
        refresh_token: 'qbo_refresh_token_123',
        expires_in: 3600,
        id_token: 'qbo_id_token_123'
      })

      allow(QboService).to receive(:validate_id_token).and_return(true)
      allow(QboService).to receive(:fetch_user_info).and_return({
        sub: 'qbo_user_sub_123',
        email: 'user@example.com',
        email_verified: true,
        given_name: 'John',
        family_name: 'Doe'
      })

      get :complete

      expect(session[:qbo_callback_params]).to be_nil
    end
  end

  describe 'DELETE #disconnect' do
    before do
      user.update(
        qbo_realm_id: 'realm_123',
        qbo_access_token: 'token_123',
        qbo_refresh_token: 'refresh_123',
        qbo_token_expires_at: 1.hour.from_now,
        qbo_connected_at: Time.current,
        qbo_id_token: 'id_token_123',
        qbo_sub_id: 'sub_123',
        qbo_user_email: 'user@example.com',
        qbo_user_email_verified: true,
        qbo_user_given_name: 'John',
        qbo_user_family_name: 'Doe'
      )
    end

    it 'disconnects QBO and clears all OAuth and OpenID fields' do
      # Mock QboService and SDK revoke_tokens! method
      qbo_service = instance_double(QboService)
      allow(QboService).to receive(:new).with(user).and_return(qbo_service)
      allow(qbo_service).to receive(:revoke_tokens!).and_return(true)

      delete :disconnect

      user.reload
      expect(user.qbo_realm_id).to be_nil
      expect(user.qbo_access_token).to be_nil
      expect(user.qbo_refresh_token).to be_nil
      expect(user.qbo_token_expires_at).to be_nil
      expect(user.qbo_connected_at).to be_nil
      expect(user.qbo_id_token).to be_nil
      expect(user.qbo_sub_id).to be_nil
      expect(user.qbo_user_email).to be_nil
      expect(user.qbo_user_email_verified).to be_nil
      expect(user.qbo_user_given_name).to be_nil
      expect(user.qbo_user_family_name).to be_nil

      expect(response).to redirect_to(dashboard_path)
      expect(flash[:notice]).to eq('QuickBooks Online disconnected successfully.')
    end

    it 'handles revocation failure and does not disconnect locally' do
      # Mock QboService revoke to fail
      qbo_service = instance_double(QboService)
      allow(QboService).to receive(:new).with(user).and_return(qbo_service)
      allow(qbo_service).to receive(:revoke_tokens!).and_return(false)

      delete :disconnect

      user.reload
      # Tokens should NOT be cleared when revocation fails
      expect(user.qbo_realm_id).to eq('realm_123')
      expect(user.qbo_access_token).to eq('token_123')
      expect(user.qbo_refresh_token).to eq('refresh_123')

      expect(response).to redirect_to(dashboard_path)
      expect(flash[:alert]).to eq('Failed to disconnect from QuickBooks. Please try again or contact support.')
    end

    it 'handles SDK errors during revocation' do
      # Mock SDK to raise OAuth error
      qbo_service = instance_double(QboService)
      allow(QboService).to receive(:new).with(user).and_return(qbo_service)
      oauth_error = StandardError.new('Network error')
      allow(qbo_service).to receive(:revoke_tokens!).and_raise(oauth_error)

      delete :disconnect

      user.reload
      # Tokens should NOT be cleared when revocation raises error
      expect(user.qbo_realm_id).to eq('realm_123')
      expect(user.qbo_access_token).to eq('token_123')

      expect(response).to redirect_to(dashboard_path)
      expect(flash[:alert]).to eq('Failed to disconnect from QuickBooks. Please try again or contact support.')
    end

    it 'disconnects locally when no connection exists' do
      # Clear tokens before test
      user.update(qbo_access_token: nil, qbo_realm_id: nil)

      delete :disconnect

      user.reload
      expect(user.qbo_connected_at).to be_nil

      expect(response).to redirect_to(dashboard_path)
      expect(flash[:notice]).to eq('QuickBooks Online disconnected successfully.')
    end
  end

  describe 'GET #status' do
    context 'when user has QBO connection' do
      before do
        user.update(
          qbo_realm_id: 'realm_123',
          qbo_access_token: 'token_123',
          qbo_token_expires_at: 1.hour.from_now,
          qbo_connected_at: Time.current
        )
      end

      it 'returns JSON status of QBO connection' do
        get :status

        expect(response).to have_http_status(:ok)
        json_response = JSON.parse(response.body)
        
        expect(json_response['connected']).to be true
        expect(json_response['valid']).to be true
        expect(json_response['realm_id']).to eq('realm_123')
        expect(json_response['connected_at']).to be_present
      end
    end

    context 'when user has no QBO connection' do
      it 'returns JSON status indicating no connection' do
        get :status

        expect(response).to have_http_status(:ok)
        json_response = JSON.parse(response.body)
        
        expect(json_response['connected']).to be false
        expect(json_response['valid']).to be false
        expect(json_response['realm_id']).to be_nil
        expect(json_response['connected_at']).to be_nil
      end
    end

  end
end