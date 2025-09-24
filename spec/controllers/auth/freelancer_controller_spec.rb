require 'rails_helper'

RSpec.describe Auth::FreelancerController, type: :controller do
  let(:user) { create(:user) }

  before do
    sign_in user
    ENV['FREELANCER_ENVIRONMENT'] = 'sandbox'
    ENV['FREELANCER_CLIENT_ID'] = 'test_client_id'
    ENV['FREELANCER_CLIENT_SECRET'] = 'test_client_secret'
  end

  describe 'GET #connect' do
    it 'redirects to Freelancer authorization URL' do
      get :connect

      expect(response).to redirect_to(/freelancer-sandbox.com/)
      expect(response.location).to include('client_id=test_client_id')
      expect(response.location).to include('scope=basic')
      expect(response.location).not_to include('advanced_scopes')
    end

    it 'uses sandbox URL for sandbox environment' do
      get :connect
      expect(response.location).to include('accounts.freelancer-sandbox.com')
    end

    it 'uses production URL for production environment' do
      ENV['FREELANCER_ENVIRONMENT'] = 'production'
      get :connect
      expect(response.location).to include('accounts.freelancer.com')
    end

    it 'sets state parameter in session' do
      get :connect
      expect(session[:freelancer_oauth_state]).to be_present
      expect(response.location).to include("state=#{session[:freelancer_oauth_state]}")
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
    before do
      session[:freelancer_oauth_state] = 'test_state_123'
    end

    it 'handles successful token exchange' do
      # Mock the controller's private methods
      allow(controller).to receive(:exchange_code_for_tokens).and_return({
        'access_token' => 'freelancer_access_token_123',
        'refresh_token' => 'freelancer_refresh_token_123',
        'expires_in' => 2592000,
        'scope' => 'basic 1 2 3'
      })

      allow(controller).to receive(:extract_user_id_from_token).and_return('12345')

      original_time = Time.current
      allow(Time).to receive(:current).and_return(original_time)

      get :callback, params: {
        code: 'auth_code_123',
        state: 'test_state_123'
      }

      user.reload
      expect(user.freelancer_user_id).to eq('12345')
      expect(user.freelancer_access_token).to eq('freelancer_access_token_123')
      expect(user.freelancer_refresh_token).to eq('freelancer_refresh_token_123')
      expect(user.freelancer_token_expires_at).to be_within(1.second).of(original_time + 2592000.seconds)
      expect(user.freelancer_scopes).to eq('basic 1 2 3')
      expect(user.freelancer_connected_at).to be_within(1.second).of(original_time)

      expect(session[:freelancer_oauth_state]).to be_nil
      expect(response).to redirect_to(dashboard_path)
      expect(flash[:notice]).to eq('Freelancer account connected successfully!')
    end

    it 'handles invalid state parameter' do
      get :callback, params: {
        code: 'auth_code_123',
        state: 'invalid_state'
      }

      user.reload
      expect(user.freelancer_user_id).to be_nil

      expect(session[:freelancer_oauth_state]).to be_nil
      expect(response).to redirect_to(dashboard_path)
      expect(flash[:alert]).to eq('Failed to connect to Freelancer. Please try again.')
    end

    it 'handles failed token exchange' do
      allow(controller).to receive(:exchange_code_for_tokens).and_raise(StandardError, 'Token exchange failed')

      get :callback, params: {
        code: 'invalid_code',
        state: 'test_state_123'
      }

      user.reload
      expect(user.freelancer_user_id).to be_nil

      expect(session[:freelancer_oauth_state]).to be_nil
      expect(response).to redirect_to(dashboard_path)
      expect(flash[:alert]).to eq('Failed to connect to Freelancer. Please try again.')
    end
  end

  describe 'DELETE #disconnect' do
    before do
      user.update(
        freelancer_user_id: '12345',
        freelancer_access_token: 'token_123',
        freelancer_refresh_token: 'refresh_123',
        freelancer_token_expires_at: 1.hour.from_now,
        freelancer_scopes: 'basic 1 2 3',
        freelancer_connected_at: Time.current
      )
    end

    it 'disconnects Freelancer and redirects with success message' do
      delete :disconnect

      user.reload
      expect(user.freelancer_user_id).to be_nil
      expect(user.freelancer_access_token).to be_nil
      expect(user.freelancer_refresh_token).to be_nil
      expect(user.freelancer_token_expires_at).to be_nil
      expect(user.freelancer_scopes).to be_nil
      expect(user.freelancer_connected_at).to be_nil

      expect(response).to redirect_to(dashboard_path)
      expect(flash[:notice]).to eq('Freelancer account disconnected successfully.')
    end
  end

  describe 'GET #status' do
    context 'when user has Freelancer connection' do
      before do
        user.update(
          freelancer_user_id: '12345',
          freelancer_access_token: 'token_123',
          freelancer_token_expires_at: 1.hour.from_now,
          freelancer_scopes: 'basic 1 2 3',
          freelancer_connected_at: Time.current
        )
      end

      it 'returns JSON status of Freelancer connection' do
        get :status

        expect(response).to have_http_status(:ok)
        json_response = JSON.parse(response.body)

        expect(json_response['connected']).to be true
        expect(json_response['valid']).to be true
        expect(json_response['user_id']).to eq('12345')
        expect(json_response['scopes']).to eq('basic 1 2 3')
        expect(json_response['connected_at']).to be_present
      end
    end

    context 'when user has no Freelancer connection' do
      it 'returns JSON status indicating no connection' do
        get :status

        expect(response).to have_http_status(:ok)
        json_response = JSON.parse(response.body)

        expect(json_response['connected']).to be false
        expect(json_response['valid']).to be false
        expect(json_response['user_id']).to be_nil
        expect(json_response['scopes']).to be_nil
        expect(json_response['connected_at']).to be_nil
      end
    end
  end

  describe 'GET #test_connection' do
    context 'when user has valid Freelancer connection' do
      before do
        user.update(
          freelancer_user_id: '12345',
          freelancer_access_token: 'valid_token',
          freelancer_token_expires_at: 1.hour.from_now,
          freelancer_connected_at: Time.current
        )
      end

      it 'returns success when connection test passes' do
        mock_service = double('FreelancerService')
        allow(FreelancerService).to receive(:new).with(user).and_return(mock_service)
        allow(mock_service).to receive(:get_user_info).and_return({
          'id' => '12345',
          'username' => 'testuser',
          'display_name' => 'Test User'
        })

        get :test_connection

        expect(response).to have_http_status(:ok)
        json_response = JSON.parse(response.body)

        expect(json_response['success']).to be true
        expect(json_response['message']).to eq('Freelancer connection successful!')
        expect(json_response['user_info']['id']).to eq('12345')
        expect(json_response['environment']).to eq('sandbox')
      end

      it 'returns error when connection test fails' do
        mock_service = double('FreelancerService')
        allow(FreelancerService).to receive(:new).with(user).and_return(mock_service)
        allow(mock_service).to receive(:get_user_info).and_return(nil)

        get :test_connection

        expect(response).to have_http_status(:service_unavailable)
        json_response = JSON.parse(response.body)

        expect(json_response['success']).to be false
        expect(json_response['error']).to eq('Failed to connect to Freelancer API')
      end

      it 'handles service exceptions' do
        allow(FreelancerService).to receive(:new).with(user).and_raise(StandardError, 'API Error')

        get :test_connection

        expect(response).to have_http_status(:service_unavailable)
        json_response = JSON.parse(response.body)

        expect(json_response['success']).to be false
        expect(json_response['error']).to eq('Connection failed: API Error')
      end
    end

    context 'when user has no valid Freelancer connection' do
      it 'returns unauthorized status' do
        get :test_connection

        expect(response).to have_http_status(:unauthorized)
        json_response = JSON.parse(response.body)

        expect(json_response['success']).to be false
        expect(json_response['error']).to eq('Freelancer not connected or token expired. Please reconnect.')
      end
    end
  end
end