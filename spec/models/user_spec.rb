require 'rails_helper'

RSpec.describe User, type: :model do
  describe 'QBO integration methods' do
    let(:user) { create(:user) }

    describe '#qbo_connected?' do
      it 'returns false when no QBO data is present' do
        expect(user.qbo_connected?).to be false
      end

      it 'returns false when only realm_id is present' do
        user.update(qbo_realm_id: '123456')
        expect(user.qbo_connected?).to be false
      end

      it 'returns false when only access_token is present' do
        user.update(qbo_access_token: 'token123')
        expect(user.qbo_connected?).to be false
      end

      it 'returns true when both realm_id and access_token are present' do
        user.update(
          qbo_realm_id: '123456',
          qbo_access_token: 'token123'
        )
        expect(user.qbo_connected?).to be true
      end
    end

    describe '#qbo_token_expired?' do
      it 'returns false when no expiration date is set' do
        expect(user.qbo_token_expired?).to be false
      end

      it 'returns false when token expiration is in the future' do
        user.update(qbo_token_expires_at: 1.hour.from_now)
        expect(user.qbo_token_expired?).to be false
      end

      it 'returns true when token expiration is in the past' do
        user.update(qbo_token_expires_at: 1.hour.ago)
        expect(user.qbo_token_expired?).to be true
      end
    end

    describe '#qbo_token_valid?' do
      it 'returns false when not connected' do
        expect(user.qbo_token_valid?).to be false
      end

      it 'returns false when connected but token is expired' do
        user.update(
          qbo_realm_id: '123456',
          qbo_access_token: 'token123',
          qbo_token_expires_at: 1.hour.ago
        )
        expect(user.qbo_token_valid?).to be false
      end

      it 'returns true when connected and token is not expired' do
        user.update(
          qbo_realm_id: '123456',
          qbo_access_token: 'token123',
          qbo_token_expires_at: 1.hour.from_now
        )
        expect(user.qbo_token_valid?).to be true
      end

      it 'returns true when connected and no expiration date is set' do
        user.update(
          qbo_realm_id: '123456',
          qbo_access_token: 'token123'
        )
        expect(user.qbo_token_valid?).to be true
      end
    end

    describe '#disconnect_qbo!' do
      before do
        user.update(
          qbo_realm_id: '123456',
          qbo_access_token: 'token123',
          qbo_refresh_token: 'refresh123',
          qbo_token_expires_at: 1.hour.from_now,
          qbo_connected_at: Time.current
        )
      end

      it 'clears all QBO-related fields' do
        user.disconnect_qbo!
        user.reload

        expect(user.qbo_realm_id).to be_nil
        expect(user.qbo_access_token).to be_nil
        expect(user.qbo_refresh_token).to be_nil
        expect(user.qbo_token_expires_at).to be_nil
        expect(user.qbo_connected_at).to be_nil
      end

      it 'makes qbo_connected? return false' do
        user.disconnect_qbo!
        expect(user.qbo_connected?).to be false
      end
    end

    describe '#can_access_feature? with QBO' do
      context 'free tier user' do
        before { user.subscription.update(status: 'free') }

        it 'cannot access qbo_integration' do
          expect(user.can_access_feature?('qbo_integration')).to be false
        end
      end

      context 'standard tier user' do
        before { user.subscription.update(status: 'standard') }

        it 'can access qbo_integration' do
          expect(user.can_access_feature?('qbo_integration')).to be true
        end
      end

      context 'premium tier user' do
        before { user.subscription.update(status: 'premium') }

        it 'can access qbo_integration' do
          expect(user.can_access_feature?('qbo_integration')).to be true
        end
      end
    end
  end
end