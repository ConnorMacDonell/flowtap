require 'rails_helper'

RSpec.describe FreelancerTokenRefreshJob, type: :job do
  let(:user) { create(:user, :with_freelancer_connection) }

  describe '#perform' do
    context 'when called without user_id (refresh all users)' do
      let!(:user_needs_refresh) { create(:user, :with_freelancer_expiring_token) }
      let!(:user_with_valid_token) { create(:user, :with_freelancer_connection) }
      let!(:user_without_freelancer) { create(:user) }

      it 'refreshes tokens for users who need it' do
        expect(FreelancerService).to receive(:new).with(user_needs_refresh).and_call_original
        expect(FreelancerService).not_to receive(:new).with(user_with_valid_token)
        expect(FreelancerService).not_to receive(:new).with(user_without_freelancer)

        allow_any_instance_of(FreelancerService).to receive(:refresh_token!).and_return(true)

        described_class.perform_now
      end

      it 'logs the number of users found' do
        allow_any_instance_of(FreelancerService).to receive(:refresh_token!).and_return(true)

        expect(Rails.logger).to receive(:info).with(/Found \d+ users needing token refresh/)

        described_class.perform_now
      end

      it 'handles individual user failures gracefully' do
        allow_any_instance_of(FreelancerService).to receive(:refresh_token!).and_raise(StandardError, 'API Error')

        expect(Rails.logger).to receive(:error).with(/Failed to refresh token for user/)

        expect { described_class.perform_now }.not_to raise_error
      end
    end

    context 'when called with specific user_id' do
      it 'refreshes token for the specified user' do
        expect(FreelancerService).to receive(:new).with(user).and_call_original
        expect_any_instance_of(FreelancerService).to receive(:refresh_token!).and_return(true)

        described_class.perform_now(user.id)
      end

      it 'logs success when token refresh succeeds' do
        allow_any_instance_of(FreelancerService).to receive(:refresh_token!).and_return(true)

        expect(Rails.logger).to receive(:info).with("FreelancerTokenRefreshJob: Successfully refreshed token for user #{user.id}")

        described_class.perform_now(user.id)
      end

      it 'logs error when token refresh fails' do
        allow_any_instance_of(FreelancerService).to receive(:refresh_token!).and_return(false)

        expect(Rails.logger).to receive(:error).with("FreelancerTokenRefreshJob: Failed to refresh token for user #{user.id}")

        described_class.perform_now(user.id)
      end

      it 'handles users who cannot refresh tokens' do
        user.update!(freelancer_refresh_token: nil)

        expect(Rails.logger).to receive(:warn).with(/cannot refresh token/)

        described_class.perform_now(user.id)
      end

      it 'handles users with expired refresh tokens' do
        user.update!(freelancer_connected_at: 7.months.ago)

        expect(Rails.logger).to receive(:warn).with(/cannot refresh token/)

        described_class.perform_now(user.id)
      end

      it 'skips users without Freelancer connection' do
        user_without_freelancer = create(:user)

        expect(Rails.logger).to receive(:debug).with(/Skipping user/)

        described_class.perform_now(user_without_freelancer.id)
      end

      it 'raises errors for retry mechanism on service failures' do
        allow(FreelancerService).to receive(:new).and_raise(StandardError, 'Service Error')

        expect(Rails.logger).to receive(:error).with(/Error refreshing token/)

        expect { described_class.perform_now(user.id) }.to raise_error(StandardError, 'Service Error')
      end
    end
  end

  describe 'job configuration' do
    it 'is configured to retry with exponential backoff' do
      expect(described_class.retry_on).to include(StandardError)
    end

    it 'discards on deserialization errors' do
      expect(described_class.discard_on).to include(ActiveJob::DeserializationError)
    end
  end
end