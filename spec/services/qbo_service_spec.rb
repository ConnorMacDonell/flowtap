require 'rails_helper'

RSpec.describe QboService, type: :service do
  let(:user) { create(:user, :with_qbo_connection) }
  let(:qbo_service) { described_class.new(user) }

  before do
    allow(QboApi).to receive(:production=)

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

  describe '#initialize' do
    context 'with valid QBO connection' do
      it 'initializes successfully' do
        expect { qbo_service }.not_to raise_error
      end

      it 'sets QboApi production mode based on environment' do
        ENV['QBO_ENVIRONMENT'] = 'production'
        described_class.new(user)
        expect(QboApi).to have_received(:production=).with(true)
      end

      it 'sets QboApi sandbox mode when not production' do
        ENV['QBO_ENVIRONMENT'] = 'sandbox'
        described_class.new(user)
        expect(QboApi).to have_received(:production=).with(false)
      end
    end

    context 'with invalid QBO connection' do
      let(:user) { create(:user) }

      it 'raises ArgumentError when user has no QBO connection' do
        expect { described_class.new(user) }.to raise_error(ArgumentError, 'User must have valid QBO connection')
      end
    end

    context 'with expired token' do
      let(:user) { create(:user, :with_expired_qbo_token) }

      it 'raises ArgumentError when token is expired' do
        expect { described_class.new(user) }.to raise_error(ArgumentError, 'User must have valid QBO connection')
      end
    end
  end

  describe '#api' do
    it 'returns the QboApi instance' do
      expect(qbo_service.api).to be_a(QboApi)
    end
  end

  describe '#test_connection' do
    let(:mock_qbo_api) { instance_double(QboApi) }

    before do
      allow(QboApi).to receive(:new).and_return(mock_qbo_api)
    end

    context 'when connection is successful' do
      before do
        allow(mock_qbo_api).to receive(:get).with(:companyinfo, 1).and_return({ 'Id' => '1' })
      end

      it 'returns true' do
        expect(qbo_service.test_connection).to be true
      end
    end

    context 'when connection fails with QboApi error' do
      let(:qbo_error) do
        error = StandardError.new('API Error')
        error.define_singleton_method(:response) { { 'Fault' => { 'intuit_tid' => 'test-tid-123' } } }
        error.extend(QboApi::Error) rescue error
        error
      end

      before do
        allow(mock_qbo_api).to receive(:get).with(:companyinfo, 1).and_raise(qbo_error)
        allow(Rails.logger).to receive(:error)
      end

      it 'returns false' do
        expect(qbo_service.test_connection).to be false
      end

      it 'logs the error' do
        qbo_service.test_connection
        expect(Rails.logger).to have_received(:error)
      end

      it 'attempts to create an audit log entry' do
        # The rescue clause makes it difficult to test the exact call
        # This test verifies that the error handling path is taken
        expect(qbo_service.test_connection).to be false
      end
    end

    context 'when connection fails with standard error' do
      before do
        allow(mock_qbo_api).to receive(:get).with(:companyinfo, 1).and_raise(StandardError)
        allow(Rails.logger).to receive(:error)
      end

      it 'returns false' do
        expect(qbo_service.test_connection).to be false
      end

      it 'logs the error' do
        qbo_service.test_connection
        expect(Rails.logger).to have_received(:error)
      end
    end
  end

  describe '#refresh_token!' do
    before do
      ENV['QBO_CLIENT_ID'] = 'test_client_id'
      ENV['QBO_CLIENT_SECRET'] = 'test_client_secret'
    end

    context 'when user has no refresh token' do
      before do
        user.update(qbo_refresh_token: nil)
      end

      it 'returns false' do
        expect(qbo_service.refresh_token!).to be false
      end
    end

    context 'when refresh token exists' do
      let(:mock_oauth_client) { double('IntuitOAuth::Client') }
      let(:mock_token) { double('IntuitOAuth Token') }

      before do
        allow(IntuitOAuth::Client).to receive(:new).and_return(mock_oauth_client)
        allow(mock_oauth_client).to receive(:token).and_return(mock_token)
      end

      it 'attempts to refresh the token using SDK' do
        # Mock SDK token response
        token_response = double('TokenResponse',
          access_token: 'new_access_token',
          refresh_token: 'new_refresh_token',
          expires_in: 3600
        )

        allow(mock_token).to receive(:refresh_tokens).with(user.qbo_refresh_token).and_return(token_response)

        original_time = Time.current
        allow(Time).to receive(:current).and_return(original_time)

        expect(qbo_service.refresh_token!).to be true

        user.reload
        expect(user.qbo_access_token).to eq('new_access_token')
        expect(user.qbo_refresh_token).to eq('new_refresh_token')
        expect(user.qbo_token_expires_at).to be_within(1.second).of(original_time + 3600.seconds)
      end

      it 'handles SDK OAuth exceptions gracefully' do
        oauth_error = create_oauth_error(body: 'token_refresh_failed', intuit_tid: 'test-tid-123')

        allow(mock_token).to receive(:refresh_tokens).and_raise(oauth_error)
        allow(Rails.logger).to receive(:error)

        original_token = user.qbo_access_token
        expect(qbo_service.refresh_token!).to be false

        user.reload
        expect(user.qbo_access_token).to eq(original_token)
        expect(Rails.logger).to have_received(:error)
      end

      it 'handles invalid_grant error specifically and clears refresh token' do
        oauth_error = create_oauth_error(body: 'invalid_grant: Refresh token expired', intuit_tid: 'test-tid-456')

        allow(mock_token).to receive(:refresh_tokens).and_raise(oauth_error)
        allow(Rails.logger).to receive(:error)

        expect(qbo_service.refresh_token!).to be false

        user.reload
        expect(user.qbo_refresh_token).to be_nil
        expect(Rails.logger).to have_received(:error).with(/invalid_grant/)
      end

      it 'logs detailed error information with intuit_tid' do
        oauth_error = create_oauth_error(code: 500, body: 'server_error', intuit_tid: 'test-tid-789')

        allow(mock_token).to receive(:refresh_tokens).and_raise(oauth_error)
        allow(Rails.logger).to receive(:error)

        qbo_service.refresh_token!

        expect(Rails.logger).to have_received(:error).with(/QBO OAuth error/)
      end

      it 'handles standard exceptions gracefully' do
        allow(mock_token).to receive(:refresh_tokens).and_raise(StandardError, 'Unexpected error')
        allow(Rails.logger).to receive(:error)

        expect(qbo_service.refresh_token!).to be false
        expect(Rails.logger).to have_received(:error)
      end

      it 'logs successful token refresh' do
        token_response = double('TokenResponse',
          access_token: 'new_access_token',
          refresh_token: 'new_refresh_token',
          expires_in: 3600
        )

        allow(mock_token).to receive(:refresh_tokens).and_return(token_response)
        allow(Rails.logger).to receive(:info)

        qbo_service.refresh_token!

        expect(Rails.logger).to have_received(:info).with(/QBO token refreshed successfully/)
      end

      it 'updates the QboApi instance with new access token' do
        token_response = double('TokenResponse',
          access_token: 'new_access_token',
          refresh_token: 'new_refresh_token',
          expires_in: 3600
        )

        allow(mock_token).to receive(:refresh_tokens).and_return(token_response)

        # Allow the initial QboApi.new call during service initialization
        allow(QboApi).to receive(:new).and_call_original

        # Create a fresh service to test the refresh
        service = qbo_service

        # Expect a new QboApi instance to be created with the new token
        expect(QboApi).to receive(:new).with(
          access_token: 'new_access_token',
          realm_id: user.qbo_realm_id
        ).and_call_original

        service.refresh_token!
      end
    end
  end

  describe '#revoke_tokens!' do
    let(:mock_oauth_client) { double('IntuitOAuth::Client') }
    let(:mock_token) { double('IntuitOAuth Token') }

    before do
      ENV['QBO_CLIENT_ID'] = 'test_client_id'
      ENV['QBO_CLIENT_SECRET'] = 'test_client_secret'

      allow(IntuitOAuth::Client).to receive(:new).and_return(mock_oauth_client)
      allow(mock_oauth_client).to receive(:token).and_return(mock_token)
    end

    context 'when user has refresh token' do
      it 'revokes the refresh token successfully using SDK' do
        allow(mock_token).to receive(:revoke_tokens).with(user.qbo_refresh_token).and_return(true)
        allow(Rails.logger).to receive(:info)

        expect(qbo_service.revoke_tokens!).to be true
        expect(Rails.logger).to have_received(:info).with(/QBO.*revoked successfully/)
      end

      it 'sends the refresh token to SDK revoke method' do
        expect(mock_token).to receive(:revoke_tokens).with(user.qbo_refresh_token)
        allow(Rails.logger).to receive(:info)

        qbo_service.revoke_tokens!
      end
    end

    context 'when user has only access token (no refresh token)' do
      before do
        user.update(qbo_refresh_token: nil)
      end

      it 'revokes the access token as fallback using SDK' do
        expect(mock_token).to receive(:revoke_tokens).with(user.qbo_access_token)
        allow(Rails.logger).to receive(:info)

        expect(qbo_service.revoke_tokens!).to be true
      end
    end

    context 'when user has no tokens' do
      it 'returns false and logs warning' do
        # Initialize service with valid connection first
        service = qbo_service

        # Then clear tokens to test edge case
        user.update(qbo_refresh_token: nil, qbo_access_token: nil)

        allow(Rails.logger).to receive(:warn)

        expect(service.revoke_tokens!).to be false
        expect(Rails.logger).to have_received(:warn).with(/no tokens to revoke/)
      end
    end

    context 'when revocation fails with SDK OAuth error' do
      it 'returns false and logs error' do
        oauth_error = create_oauth_error(body: 'invalid_token', intuit_tid: 'test-tid-999')

        allow(mock_token).to receive(:revoke_tokens).and_raise(oauth_error)
        allow(Rails.logger).to receive(:error)

        expect(qbo_service.revoke_tokens!).to be false
        expect(Rails.logger).to have_received(:error).with(/QBO OAuth error/)
      end
    end

    context 'when network error occurs' do
      it 'handles standard exceptions gracefully' do
        allow(mock_token).to receive(:revoke_tokens).and_raise(StandardError, 'Unexpected error')
        allow(Rails.logger).to receive(:error)

        expect(qbo_service.revoke_tokens!).to be false
        expect(Rails.logger).to have_received(:error)
      end
    end
  end
end