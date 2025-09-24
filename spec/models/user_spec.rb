require 'rails_helper'

RSpec.describe User, type: :model do
  let(:user) { create(:user) }

  describe 'validations' do
    it 'validates presence of email' do
      user = build(:user, email: nil)
      expect(user).not_to be_valid
      expect(user.errors[:email]).to include("can't be blank")
    end

    it 'validates presence of first_name' do
      user = build(:user, first_name: nil)
      expect(user).not_to be_valid
      expect(user.errors[:first_name]).to include("can't be blank")
    end

    it 'validates presence of last_name' do
      user = build(:user, last_name: nil)
      expect(user).not_to be_valid
      expect(user.errors[:last_name]).to include("can't be blank")
    end

    it 'validates presence of timezone' do
      user = build(:user, timezone: nil)
      expect(user).not_to be_valid
      expect(user.errors[:timezone]).to include("can't be blank")
    end
    
    it 'validates length of first_name' do
      user = build(:user, first_name: 'a' * 51)
      expect(user).not_to be_valid
      expect(user.errors[:first_name]).to include("is too long (maximum is 50 characters)")
    end

    it 'validates length of last_name' do
      user = build(:user, last_name: 'a' * 51)
      expect(user).not_to be_valid
      expect(user.errors[:last_name]).to include("is too long (maximum is 50 characters)")
    end
    
    it 'validates uniqueness of email' do
      existing_user = create(:user, email: 'test@example.com')
      user = build(:user, email: 'test@example.com')
      expect(user).not_to be_valid
      expect(user.errors[:email]).to include("has already been taken")
    end

    describe 'email format validation' do
      it 'accepts valid email addresses' do
        valid_emails = ['test@example.com', 'user.name+tag@domain.co.uk', 'x@y.co']
        valid_emails.each do |email|
          user = build(:user, email: email)
          expect(user).to be_valid, "#{email} should be valid"
        end
      end

      it 'rejects invalid email addresses' do
        invalid_emails = ['plainaddress', '@missingdomain.com', 'spaces @domain.com']
        invalid_emails.each do |email|
          user = build(:user, email: email)
          expect(user).not_to be_valid, "#{email} should be invalid"
        end
      end
    end
  end

  describe 'associations' do
    it 'has one subscription' do
      expect(user.association(:subscription)).to be_present
      expect(user.subscription).to be_nil  # Since we removed auto-creation
    end
  end

  describe 'scopes' do
    before do
      @confirmed_user = create(:user, confirmed_at: 1.day.ago)
      @unconfirmed_user = create(:user, confirmed_at: nil)
      @deleted_user = create(:user, deleted_at: 1.day.ago)
      @active_user = create(:user, confirmed_at: 1.day.ago, deleted_at: nil)
    end

    describe '.confirmed' do
      it 'returns only confirmed users' do
        expect(User.confirmed).to include(@confirmed_user, @active_user)
        expect(User.confirmed).not_to include(@unconfirmed_user)
      end
    end

    describe '.unconfirmed' do
      it 'returns only unconfirmed users' do
        expect(User.unconfirmed).to include(@unconfirmed_user)
        expect(User.unconfirmed).not_to include(@confirmed_user, @active_user)
      end
    end

    describe '.not_deleted' do
      it 'returns only non-deleted users' do
        expect(User.not_deleted).to include(@confirmed_user, @unconfirmed_user, @active_user)
        expect(User.not_deleted).not_to include(@deleted_user)
      end
    end

    describe '.deleted' do
      it 'returns only soft-deleted users' do
        expect(User.deleted).to include(@deleted_user)
        expect(User.deleted).not_to include(@confirmed_user, @unconfirmed_user, @active_user)
      end
    end
  end

  describe 'signup process' do
    describe 'user creation' do
      it 'creates a user with valid attributes' do
        user_params = {
          email: 'newuser@example.com',
          password: 'password123',
          first_name: 'John',
          last_name: 'Doe',
          timezone: 'America/New_York'
        }
        
        user = User.new(user_params)
        expect(user).to be_valid
        expect { user.save! }.to change(User, :count).by(1)
      end

      it 'does not create a subscription automatically on signup' do
        user_params = {
          email: 'newuser@example.com',
          password: 'password123',
          first_name: 'John',
          last_name: 'Doe',
          timezone: 'America/New_York'
        }
        
        user = User.create!(user_params)
        expect(user.subscription).to be_nil
      end

      it 'starts unconfirmed' do
        user = build(:user, confirmed_at: nil)
        user.save!
        expect(user.confirmed_at).to be_nil
        expect(user).not_to be_confirmed
      end

      it 'requires password on creation' do
        user = build(:user, password: nil, password_confirmation: nil)
        expect(user).not_to be_valid
        expect(user.errors[:password]).to include("can't be blank")
      end

      it 'requires password confirmation to match' do
        user = build(:user, password: 'password123', password_confirmation: 'different')
        expect(user).not_to be_valid
        expect(user.errors[:password_confirmation]).to include("doesn't match Password")
      end
    end

    describe 'confirmation process' do
      let(:unconfirmed_user) { create(:user, confirmed_at: nil) }

      it 'sends welcome email when user confirms their account' do
        expect(UserMailer).to receive(:welcome_email).with(unconfirmed_user).and_call_original
        expect_any_instance_of(ActionMailer::MessageDelivery).to receive(:deliver_now)
        
        unconfirmed_user.update!(confirmed_at: Time.current)
      end

      it 'does not send welcome email on other updates' do
        confirmed_user = create(:user, confirmed_at: 1.day.ago)
        
        expect(UserMailer).not_to receive(:welcome_email)
        
        confirmed_user.update!(first_name: 'Updated')
      end

      it 'becomes confirmed after confirmation' do
        expect(unconfirmed_user).not_to be_confirmed
        
        unconfirmed_user.confirm
        
        expect(unconfirmed_user.reload).to be_confirmed
        expect(unconfirmed_user.confirmed_at).to be_present
      end
    end
  end

  describe 'QBO integration methods' do

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

    describe '#can_access_feature?' do
      context 'user without active subscription' do
        it 'cannot access qbo_integration' do
          expect(user.can_access_feature?('qbo_integration')).to be false
        end
      end

      context 'user with paid subscription' do
        before { create(:subscription, user: user, status: 'paid') }

        it 'can access qbo_integration' do
          expect(user.can_access_feature?('qbo_integration')).to be true
        end
      end
    end

    # Freelancer Integration Tests
    describe '#freelancer_connected?' do
      it 'returns false when user has no freelancer connection' do
        expect(user.freelancer_connected?).to be false
      end

      it 'returns false when user has partial freelancer connection' do
        user.update(freelancer_user_id: '12345')
        expect(user.freelancer_connected?).to be false
      end

      it 'returns true when user has complete freelancer connection' do
        user.update(
          freelancer_user_id: '12345',
          freelancer_access_token: 'token123'
        )
        expect(user.freelancer_connected?).to be true
      end
    end

    describe '#freelancer_token_expired?' do
      it 'returns false when no expiration time is set' do
        expect(user.freelancer_token_expired?).to be false
      end

      it 'returns true when token has expired' do
        user.update(freelancer_token_expires_at: 1.hour.ago)
        expect(user.freelancer_token_expired?).to be true
      end

      it 'returns false when token has not expired' do
        user.update(freelancer_token_expires_at: 1.hour.from_now)
        expect(user.freelancer_token_expired?).to be false
      end
    end

    describe '#freelancer_token_valid?' do
      it 'returns false when not connected' do
        expect(user.freelancer_token_valid?).to be false
      end

      it 'returns false when connected but token expired' do
        user.update(
          freelancer_user_id: '12345',
          freelancer_access_token: 'token123',
          freelancer_token_expires_at: 1.hour.ago
        )
        expect(user.freelancer_token_valid?).to be false
      end

      it 'returns true when connected and token valid' do
        user.update(
          freelancer_user_id: '12345',
          freelancer_access_token: 'token123',
          freelancer_token_expires_at: 1.hour.from_now
        )
        expect(user.freelancer_token_valid?).to be true
      end
    end

    describe '#freelancer_scopes_array' do
      it 'returns empty array when no scopes set' do
        expect(user.freelancer_scopes_array).to eq([])
      end

      it 'returns empty array when scopes is empty string' do
        user.update(freelancer_scopes: '')
        expect(user.freelancer_scopes_array).to eq([])
      end

      it 'returns array of scopes when scopes are set' do
        user.update(freelancer_scopes: 'basic 1 2 3')
        expect(user.freelancer_scopes_array).to eq(['basic', '1', '2', '3'])
      end
    end

    describe '#has_freelancer_scope?' do
      before do
        user.update(freelancer_scopes: 'basic 1 2 5')
      end

      it 'returns true when user has the specified scope' do
        expect(user.has_freelancer_scope?('basic')).to be true
        expect(user.has_freelancer_scope?(1)).to be true
        expect(user.has_freelancer_scope?('2')).to be true
      end

      it 'returns false when user does not have the specified scope' do
        expect(user.has_freelancer_scope?('3')).to be false
        expect(user.has_freelancer_scope?(4)).to be false
      end

      it 'returns false when no scopes are set' do
        user.update(freelancer_scopes: nil)
        expect(user.has_freelancer_scope?('basic')).to be false
      end
    end

    describe '#disconnect_freelancer!' do
      before do
        user.update(
          freelancer_user_id: '12345',
          freelancer_access_token: 'token123',
          freelancer_refresh_token: 'refresh123',
          freelancer_token_expires_at: 1.hour.from_now,
          freelancer_scopes: 'basic 1 2 3',
          freelancer_connected_at: Time.current
        )
      end

      it 'clears all Freelancer-related fields' do
        user.disconnect_freelancer!
        user.reload

        expect(user.freelancer_user_id).to be_nil
        expect(user.freelancer_access_token).to be_nil
        expect(user.freelancer_refresh_token).to be_nil
        expect(user.freelancer_token_expires_at).to be_nil
        expect(user.freelancer_scopes).to be_nil
        expect(user.freelancer_connected_at).to be_nil
      end

      it 'makes freelancer_connected? return false' do
        user.disconnect_freelancer!
        expect(user.freelancer_connected?).to be false
      end
    end
  end
end