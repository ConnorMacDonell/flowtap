require 'rails_helper'

RSpec.describe FreelancerService, 'Token refresh functionality', type: :service do
  let(:user) { create(:user, :with_freelancer_connection) }
  let(:service) { described_class.new(user) }

  before do
    ENV['FREELANCER_ENVIRONMENT'] = 'sandbox'
    ENV['FREELANCER_CLIENT_ID'] = 'test_client_id'
    ENV['FREELANCER_CLIENT_SECRET'] = 'test_client_secret'
  end

  describe '#initialize with token refresh scenarios' do
    context 'when user has expired token but can refresh' do
      let(:user) { create(:user, :with_expired_freelancer_token) }

      it 'allows initialization' do
        expect { described_class.new(user) }.not_to raise_error
      end
    end

    context 'when user has expired refresh token' do
      let(:user) { create(:user, :with_expired_freelancer_refresh_token) }

      it 'raises ArgumentError' do
        expect { described_class.new(user) }.to raise_error(ArgumentError, /connection or ability to refresh/)
      end
    end

    context 'when user has no Freelancer connection' do
      let(:user) { create(:user) }

      it 'raises ArgumentError' do
        expect { described_class.new(user) }.to raise_error(ArgumentError, /connection or ability to refresh/)
      end
    end
  end

  describe '#refresh_token!' do
    let(:token_refresh_response) do
      {
        'access_token' => 'new_access_token_123',
        'refresh_token' => 'new_refresh_token_123',
        'expires_in' => 3600,
        'scope' => 'basic 1 2 3'
      }
    end

    before do
      stub_request(:post, 'https://accounts.freelancer-sandbox.com/oauth/token')
        .with(
          body: hash_including(
            'grant_type' => 'refresh_token',
            'refresh_token' => user.freelancer_refresh_token,
            'client_id' => 'test_client_id',
            'client_secret' => 'test_client_secret'
          )
        )
        .to_return(
          status: 200,
          body: token_refresh_response.to_json,
          headers: { 'Content-Type' => 'application/json' }
        )
    end

    context 'when user can refresh token' do
      let(:user) { create(:user, :with_expired_freelancer_token) }

      it 'successfully refreshes the token' do
        original_time = Time.current
        allow(Time).to receive(:current).and_return(original_time)

        result = service.refresh_token!

        expect(result).to be true

        user.reload
        expect(user.freelancer_access_token).to eq('new_access_token_123')
        expect(user.freelancer_refresh_token).to eq('new_refresh_token_123')
        expect(user.freelancer_token_expires_at).to be_within(1.second).of(original_time + 3600.seconds)
        expect(user.freelancer_scopes).to eq('basic 1 2 3')
      end

      it 'logs successful refresh' do
        expect(Rails.logger).to receive(:info).with(/Attempting to refresh token/)
        expect(Rails.logger).to receive(:info).with(/Successfully refreshed token/)

        service.refresh_token!
      end

      it 'resets token_refresh_attempted flag on success' do
        service.instance_variable_set(:@token_refresh_attempted, true)
        service.refresh_token!
        expect(service.instance_variable_get(:@token_refresh_attempted)).to be false
      end
    end

    context 'when refresh token API call fails' do
      before do
        stub_request(:post, 'https://accounts.freelancer-sandbox.com/oauth/token')
          .to_return(status: 400, body: { error: 'invalid_grant' }.to_json)
      end

      it 'returns false and logs error' do
        expect(Rails.logger).to receive(:error).with(/token refresh failed/)

        result = service.refresh_token!
        expect(result).to be false
      end

      it 'logs warning for invalid_grant errors' do
        expect(Rails.logger).to receive(:warn).with(/refresh token appears invalid/)

        service.refresh_token!
      end
    end

    context 'when response lacks access_token' do
      let(:invalid_response) { { 'expires_in' => 3600 } }

      before do
        stub_request(:post, 'https://accounts.freelancer-sandbox.com/oauth/token')
          .to_return(status: 200, body: invalid_response.to_json)
      end

      it 'returns false and logs error' do
        expect(Rails.logger).to receive(:error).with(/No access_token in response/)

        result = service.refresh_token!
        expect(result).to be false
      end
    end

    context 'when user cannot refresh token' do
      before do
        allow(user).to receive(:freelancer_can_refresh?).and_return(false)
      end

      it 'returns false without making API call' do
        expect_any_instance_of(Faraday::Connection).not_to receive(:post)

        result = service.refresh_token!
        expect(result).to be false
      end
    end

    context 'when network error occurs' do
      before do
        stub_request(:post, 'https://accounts.freelancer-sandbox.com/oauth/token')
          .to_raise(Faraday::ConnectionFailed)
      end

      it 'returns false and logs error' do
        expect(Rails.logger).to receive(:error).with(/token refresh error/)

        result = service.refresh_token!
        expect(result).to be false
      end
    end

    context 'when response has default expires_in' do
      let(:response_without_expires) do
        {
          'access_token' => 'new_access_token_123',
          'refresh_token' => 'new_refresh_token_123'
        }
      end

      before do
        stub_request(:post, 'https://accounts.freelancer-sandbox.com/oauth/token')
          .to_return(status: 200, body: response_without_expires.to_json)
      end

      it 'uses default expiration time' do
        original_time = Time.current
        allow(Time).to receive(:current).and_return(original_time)

        service.refresh_token!

        user.reload
        expect(user.freelancer_token_expires_at).to be_within(1.second).of(original_time + 2592000.seconds)
      end
    end
  end

  describe '#make_request with automatic token refresh' do
    let(:user_info_response) do
      {
        'result' => {
          'id' => '12345',
          'username' => 'testuser',
          'display_name' => 'Test User'
        }
      }
    end

    before do
      # Stub the user info API call
      stub_request(:get, 'https://www.freelancer-sandbox.com/api/users/0.1/self/')
        .with(headers: { 'Freelancer-OAuth-V1' => user.freelancer_access_token })
        .to_return(status: 200, body: user_info_response.to_json)
    end

    context 'when token expires soon' do
      let(:user) { create(:user, :with_freelancer_expiring_token) }

      it 'proactively refreshes token before making request' do
        expect(service).to receive(:refresh_token!).and_return(true)
        expect(Rails.logger).to receive(:info).with(/Proactively refreshing token/)

        service.get_user_info
      end
    end

    context 'when API returns 401 and token can be refreshed' do
      before do
        # First call returns 401, second call (after refresh) returns success
        stub_request(:get, 'https://www.freelancer-sandbox.com/api/users/0.1/self/')
          .to_return(
            { status: 401, body: { error: 'unauthorized' }.to_json },
            { status: 200, body: user_info_response.to_json }
          )

        # Stub token refresh
        stub_request(:post, 'https://accounts.freelancer-sandbox.com/oauth/token')
          .to_return(
            status: 200,
            body: {
              'access_token' => 'refreshed_token',
              'refresh_token' => 'new_refresh_token',
              'expires_in' => 3600
            }.to_json
          )
      end

      it 'automatically refreshes token and retries request' do
        expect(Rails.logger).to receive(:info).with(/Attempting token refresh due to 401/)

        result = service.get_user_info
        expect(result).to eq(user_info_response)
      end

      it 'only attempts refresh once per request' do
        expect(service).to receive(:refresh_token!).once.and_return(true)

        service.get_user_info
      end
    end

    context 'when token cannot be refreshed and is expired' do
      let(:user) { create(:user, :with_expired_freelancer_refresh_token) }

      it 'raises ArgumentError' do
        expect { described_class.new(user) }.to raise_error(ArgumentError, /reauthorize/)
      end
    end
  end

  describe '#ensure_valid_token!' do
    context 'when token needs refresh and can refresh' do
      let(:user) { create(:user, :with_freelancer_expiring_token) }

      it 'calls refresh_token!' do
        expect(service).to receive(:refresh_token!).and_return(true)

        service.send(:ensure_valid_token!)
      end
    end

    context 'when token is expired and cannot refresh' do
      before do
        allow(user).to receive(:freelancer_token_expired?).and_return(true)
        allow(user).to receive(:freelancer_can_refresh?).and_return(false)
      end

      it 'raises ArgumentError about reauthorization' do
        expect { service.send(:ensure_valid_token!) }.to raise_error(ArgumentError, /reauthorize/)
      end
    end

    context 'when no valid token and cannot refresh' do
      before do
        allow(user).to receive(:freelancer_token_valid?).and_return(false)
        allow(user).to receive(:freelancer_can_refresh?).and_return(false)
      end

      it 'raises ArgumentError about authorization' do
        expect { service.send(:ensure_valid_token!) }.to raise_error(ArgumentError, /authorize/)
      end
    end
  end
end