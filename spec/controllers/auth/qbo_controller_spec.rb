require 'rails_helper'

RSpec.describe Auth::QboController, type: :controller do
  let(:user) { create(:user) }

  before do
    sign_in user
    ENV['QBO_CLIENT_ID'] = 'test_client_id'
    ENV['QBO_CLIENT_SECRET'] = 'test_client_secret'
  end

  describe 'GET #connect' do
    it 'redirects to QBO authorization URL' do
      get :connect
      
      expect(response).to redirect_to(/appcenter/)
      expect(response.location).to include('client_id=test_client_id')
      expect(response.location).to include('scope=com.intuit.quickbooks.accounting')
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
    it 'handles successful token exchange' do
      # Set session state for OAuth validation
      session[:qbo_oauth_state] = 'test_state_123'

      # Mock the controller's private method directly
      allow(controller).to receive(:exchange_code_for_tokens).and_return({
        'access_token' => 'qbo_access_token_123',
        'refresh_token' => 'qbo_refresh_token_123',
        'expires_in' => 3600
      })

      original_time = Time.current
      allow(Time).to receive(:current).and_return(original_time)

      get :callback, params: { code: 'auth_code_123', realmId: 'realm_123', state: 'test_state_123' }

      user.reload
      expect(user.qbo_realm_id).to eq('realm_123')
      expect(user.qbo_access_token).to eq('qbo_access_token_123')
      expect(user.qbo_refresh_token).to eq('qbo_refresh_token_123')
      expect(user.qbo_token_expires_at).to be_within(1.second).of(original_time + 3600.seconds)
      expect(user.qbo_connected_at).to be_within(1.second).of(original_time)

      expect(response).to redirect_to(dashboard_path)
      expect(flash[:notice]).to eq('QuickBooks Online connected successfully!')
    end

    it 'handles failed token exchange' do
      # Set session state for OAuth validation
      session[:qbo_oauth_state] = 'test_state_123'

      allow(controller).to receive(:exchange_code_for_tokens).and_raise(StandardError, 'Token exchange failed')

      get :callback, params: { code: 'invalid_code', realmId: 'realm_123', state: 'test_state_123' }

      user.reload
      expect(user.qbo_realm_id).to be_nil

      expect(response).to redirect_to(dashboard_path)
      expect(flash[:alert]).to eq('Failed to connect to QuickBooks Online. Please try again.')
    end
  end

  describe 'DELETE #disconnect' do
    before do
      user.update(
        qbo_realm_id: 'realm_123',
        qbo_access_token: 'token_123',
        qbo_refresh_token: 'refresh_123',
        qbo_token_expires_at: 1.hour.from_now,
        qbo_connected_at: Time.current
      )
    end

    it 'disconnects QBO and redirects with success message' do
      # Stub the revoke endpoint call
      stub_request(:post, "https://developer.api.intuit.com/v2/oauth2/tokens/revoke")
        .with(
          body: hash_including("token" => "refresh_123"),
          headers: {
            'Authorization' => "Basic #{Base64.strict_encode64('test_client_id:test_client_secret')}",
            'Content-Type' => 'application/json'
          }
        )
        .to_return(status: 200, body: "", headers: {})

      delete :disconnect

      user.reload
      expect(user.qbo_realm_id).to be_nil
      expect(user.qbo_access_token).to be_nil
      expect(user.qbo_refresh_token).to be_nil
      expect(user.qbo_token_expires_at).to be_nil
      expect(user.qbo_connected_at).to be_nil

      expect(response).to redirect_to(dashboard_path)
      expect(flash[:notice]).to eq('QuickBooks Online disconnected successfully.')
    end

    it 'handles revocation failure and does not disconnect locally' do
      # Stub the revoke endpoint to fail
      stub_request(:post, "https://developer.api.intuit.com/v2/oauth2/tokens/revoke")
        .to_return(status: 400, body: { error: 'invalid_token' }.to_json, headers: { 'Content-Type' => 'application/json' })

      delete :disconnect

      user.reload
      # Tokens should NOT be cleared when revocation fails
      expect(user.qbo_realm_id).to eq('realm_123')
      expect(user.qbo_access_token).to eq('token_123')
      expect(user.qbo_refresh_token).to eq('refresh_123')

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