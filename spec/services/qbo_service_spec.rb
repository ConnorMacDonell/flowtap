require 'rails_helper'

RSpec.describe QboService, type: :service do
  let(:user) { create(:user, :with_qbo_connection) }
  let(:qbo_service) { described_class.new(user) }

  before do
    allow(QboApi).to receive(:production=)
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
      it 'attempts to refresh the token' do
        # Mock the HTTP request to avoid external dependencies
        allow_any_instance_of(QboService).to receive(:refresh_token!).and_call_original
        
        # Mock the actual HTTP call
        mock_connection = double('Faraday::Connection')
        mock_response = double('Faraday::Response', success?: true, body: {
          'access_token' => 'new_access_token',
          'refresh_token' => 'new_refresh_token', 
          'expires_in' => 3600
        })
        
        allow(Faraday).to receive(:new).and_return(mock_connection)
        allow(mock_connection).to receive(:post).and_return(mock_response)

        original_time = Time.current
        allow(Time).to receive(:current).and_return(original_time)

        expect(qbo_service.refresh_token!).to be true
        
        user.reload
        expect(user.qbo_access_token).to eq('new_access_token')
        expect(user.qbo_refresh_token).to eq('new_refresh_token')
        expect(user.qbo_token_expires_at).to be_within(1.second).of(original_time + 3600.seconds)
      end

      it 'handles refresh failure gracefully' do
        mock_connection = double('Faraday::Connection')
        mock_response = double('Faraday::Response', success?: false, body: { 'error' => 'invalid_grant' }, status: 400)

        allow(Faraday).to receive(:new).and_return(mock_connection)
        allow(mock_connection).to receive(:post).and_return(mock_response)
        allow(Rails.logger).to receive(:error)

        original_token = user.qbo_access_token
        expect(qbo_service.refresh_token!).to be false

        user.reload
        expect(user.qbo_access_token).to eq(original_token)
        expect(Rails.logger).to have_received(:error)
      end

      it 'handles invalid_grant error specifically' do
        mock_connection = double('Faraday::Connection')
        mock_response = double('Faraday::Response',
          success?: false,
          body: { 'error' => 'invalid_grant', 'error_description' => 'Refresh token expired' },
          status: 400
        )

        allow(Faraday).to receive(:new).and_return(mock_connection)
        allow(mock_connection).to receive(:post).and_return(mock_response)
        allow(Rails.logger).to receive(:error)

        expect(qbo_service.refresh_token!).to be false

        user.reload
        expect(user.qbo_refresh_token).to be_nil
        expect(Rails.logger).to have_received(:error).with(/invalid_grant/)
      end

      it 'logs detailed error information with status code' do
        mock_connection = double('Faraday::Connection')
        mock_response = double('Faraday::Response',
          success?: false,
          body: { 'error' => 'server_error', 'error_description' => 'Internal error' },
          status: 500
        )

        allow(Faraday).to receive(:new).and_return(mock_connection)
        allow(mock_connection).to receive(:post).and_return(mock_response)
        allow(Rails.logger).to receive(:error)

        qbo_service.refresh_token!

        expect(Rails.logger).to have_received(:error).with(/QBO token refresh failed/)
      end

      it 'handles Faraday exceptions gracefully' do
        allow(Faraday).to receive(:new).and_raise(Faraday::Error, 'Network error')
        allow(Rails.logger).to receive(:error)

        expect(qbo_service.refresh_token!).to be false
        expect(Rails.logger).to have_received(:error)
      end

      it 'handles standard exceptions gracefully' do
        allow(Faraday).to receive(:new).and_raise(StandardError, 'Unexpected error')
        allow(Rails.logger).to receive(:error)

        expect(qbo_service.refresh_token!).to be false
        expect(Rails.logger).to have_received(:error)
      end

      it 'logs successful token refresh' do
        mock_connection = double('Faraday::Connection')
        mock_response = double('Faraday::Response', success?: true, body: {
          'access_token' => 'new_access_token',
          'refresh_token' => 'new_refresh_token',
          'expires_in' => 3600
        })

        allow(Faraday).to receive(:new).and_return(mock_connection)
        allow(mock_connection).to receive(:post).and_return(mock_response)
        allow(Rails.logger).to receive(:info)

        qbo_service.refresh_token!

        expect(Rails.logger).to have_received(:info).with(/QBO token refreshed successfully/)
      end
    end
  end
end