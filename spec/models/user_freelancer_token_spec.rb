require 'rails_helper'

RSpec.describe User, 'Freelancer token management', type: :model do
  let(:user) { create(:user) }

  describe '#freelancer_token_expires_soon?' do
    context 'when user has no token expiration' do
      it 'returns false' do
        expect(user.freelancer_token_expires_soon?).to be false
      end
    end

    context 'when token expires within threshold' do
      it 'returns true for default threshold (7 days)' do
        user.update!(freelancer_token_expires_at: 3.days.from_now)
        expect(user.freelancer_token_expires_soon?).to be true
      end

      it 'returns true for custom threshold' do
        user.update!(freelancer_token_expires_at: 2.days.from_now)
        expect(user.freelancer_token_expires_soon?(3)).to be true
      end
    end

    context 'when token expires beyond threshold' do
      it 'returns false' do
        user.update!(freelancer_token_expires_at: 10.days.from_now)
        expect(user.freelancer_token_expires_soon?).to be false
      end
    end
  end

  describe '#freelancer_refresh_token_expired?' do
    context 'when user has no refresh token' do
      it 'returns true' do
        expect(user.freelancer_refresh_token_expired?).to be true
      end
    end

    context 'when user has no connection date' do
      it 'returns false' do
        user.update!(freelancer_refresh_token: 'token123')
        expect(user.freelancer_refresh_token_expired?).to be false
      end
    end

    context 'when connection is recent' do
      it 'returns false' do
        user.update!(
          freelancer_refresh_token: 'token123',
          freelancer_connected_at: 1.month.ago
        )
        expect(user.freelancer_refresh_token_expired?).to be false
      end
    end

    context 'when connection is old' do
      it 'returns true' do
        user.update!(
          freelancer_refresh_token: 'token123',
          freelancer_connected_at: 7.months.ago
        )
        expect(user.freelancer_refresh_token_expired?).to be true
      end
    end
  end

  describe '#freelancer_needs_refresh?' do
    context 'when user is not connected' do
      it 'returns false' do
        expect(user.freelancer_needs_refresh?).to be false
      end
    end

    context 'when user is connected with valid token' do
      it 'returns false' do
        user.update!(
          freelancer_user_id: '123',
          freelancer_access_token: 'token',
          freelancer_token_expires_at: 10.days.from_now
        )
        expect(user.freelancer_needs_refresh?).to be false
      end
    end

    context 'when token is expired' do
      it 'returns true' do
        user.update!(
          freelancer_user_id: '123',
          freelancer_access_token: 'token',
          freelancer_token_expires_at: 1.hour.ago
        )
        expect(user.freelancer_needs_refresh?).to be true
      end
    end

    context 'when token expires soon' do
      it 'returns true' do
        user.update!(
          freelancer_user_id: '123',
          freelancer_access_token: 'token',
          freelancer_token_expires_at: 3.days.from_now
        )
        expect(user.freelancer_needs_refresh?).to be true
      end
    end
  end

  describe '#freelancer_can_refresh?' do
    context 'when user has no refresh token' do
      it 'returns false' do
        expect(user.freelancer_can_refresh?).to be false
      end
    end

    context 'when refresh token is expired' do
      it 'returns false' do
        user.update!(
          freelancer_refresh_token: 'token',
          freelancer_connected_at: 7.months.ago
        )
        expect(user.freelancer_can_refresh?).to be false
      end
    end

    context 'when refresh token is valid' do
      it 'returns true' do
        user.update!(
          freelancer_refresh_token: 'token',
          freelancer_connected_at: 1.month.ago
        )
        expect(user.freelancer_can_refresh?).to be true
      end
    end
  end

  describe 'integration scenarios' do
    context 'newly connected user' do
      let(:user) { create(:user, :with_freelancer_connection) }

      it 'has valid token and does not need refresh' do
        expect(user.freelancer_connected?).to be true
        expect(user.freelancer_token_valid?).to be true
        expect(user.freelancer_needs_refresh?).to be false
        expect(user.freelancer_can_refresh?).to be true
      end
    end

    context 'user with expiring token' do
      let(:user) { create(:user, :with_freelancer_expiring_token) }

      it 'needs refresh and can refresh' do
        expect(user.freelancer_connected?).to be true
        expect(user.freelancer_token_valid?).to be true
        expect(user.freelancer_needs_refresh?).to be true
        expect(user.freelancer_can_refresh?).to be true
      end
    end

    context 'user with expired token but valid refresh token' do
      let(:user) { create(:user, :with_expired_freelancer_token) }

      it 'needs refresh and can refresh' do
        expect(user.freelancer_connected?).to be true
        expect(user.freelancer_token_valid?).to be false
        expect(user.freelancer_needs_refresh?).to be true
        expect(user.freelancer_can_refresh?).to be true
      end
    end

    context 'user with expired refresh token' do
      let(:user) { create(:user, :with_expired_freelancer_refresh_token) }

      it 'needs refresh but cannot refresh' do
        expect(user.freelancer_connected?).to be true
        expect(user.freelancer_token_valid?).to be false
        expect(user.freelancer_needs_refresh?).to be true
        expect(user.freelancer_can_refresh?).to be false
      end
    end
  end
end