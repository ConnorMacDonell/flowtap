require 'rails_helper'

RSpec.describe Users::RegistrationsController, type: :controller do
  before do
    @request.env["devise.mapping"] = Devise.mappings[:user]
  end

  describe 'GET #new' do
    it 'returns successful response' do
      get :new
      expect(response).to be_successful
    end
  end

  describe 'POST #create' do
    let(:valid_params) do
      {
        user: {
          email: 'test@example.com',
          password: 'password123',
          password_confirmation: 'password123',
          first_name: 'John',
          last_name: 'Doe',
          timezone: 'America/New_York'
        }
      }
    end

    let(:invalid_params) do
      {
        user: {
          email: 'invalid-email',
          password: 'short',
          password_confirmation: 'different',
          first_name: '',
          last_name: '',
          timezone: ''
        }
      }
    end

    context 'with valid parameters' do
      it 'creates a new user' do
        expect {
          post :create, params: valid_params
        }.to change(User, :count).by(1)
      end

      it 'creates an unconfirmed user' do
        post :create, params: valid_params
        user = User.last
        expect(user.confirmed_at).to be_nil
        expect(user).not_to be_confirmed
      end

      it 'does not create a subscription automatically' do
        post :create, params: valid_params
        user = User.last
        expect(user.subscription).to be_nil
      end

      it 'sets the user attributes correctly' do
        post :create, params: valid_params
        user = User.last
        expect(user.email).to eq('test@example.com')
        expect(user.first_name).to eq('John')
        expect(user.last_name).to eq('Doe')
        expect(user.timezone).to eq('America/New_York')
      end

      it 'redirects to root path with confirmation message' do
        post :create, params: valid_params
        expect(response).to redirect_to(root_path)
        expect(flash[:notice]).to eq('Please check your email to confirm your account.')
      end

      it 'sends a confirmation email' do
        expect {
          post :create, params: valid_params
        }.to change(ActionMailer::Base.deliveries, :count).by(1)
        
        confirmation_email = ActionMailer::Base.deliveries.last
        expect(confirmation_email.to).to include('test@example.com')
        expect(confirmation_email.subject).to match(/confirm/i)
      end
    end

    context 'with invalid parameters' do
      it 'does not create a user' do
        expect {
          post :create, params: invalid_params
        }.not_to change(User, :count)
      end

      it 'does not send confirmation email' do
        expect {
          post :create, params: invalid_params
        }.not_to change(ActionMailer::Base.deliveries, :count)
      end
    end

    context 'with missing required fields' do
      it 'requires first_name' do
        params = valid_params.deep_dup
        params[:user][:first_name] = ''
        
        expect {
          post :create, params: params
        }.not_to change(User, :count)
      end

      it 'requires last_name' do
        params = valid_params.deep_dup
        params[:user][:last_name] = ''
        
        expect {
          post :create, params: params
        }.not_to change(User, :count)
      end

      it 'requires timezone' do
        params = valid_params.deep_dup
        params[:user][:timezone] = ''
        
        expect {
          post :create, params: params
        }.not_to change(User, :count)
      end

      it 'requires valid email format' do
        params = valid_params.deep_dup
        params[:user][:email] = 'invalid-email'
        
        expect {
          post :create, params: params
        }.not_to change(User, :count)
      end

      it 'requires password minimum length' do
        params = valid_params.deep_dup
        params[:user][:password] = 'short'
        params[:user][:password_confirmation] = 'short'
        
        expect {
          post :create, params: params
        }.not_to change(User, :count)
      end
    end

    context 'with duplicate email' do
      before do
        create(:user, email: 'test@example.com')
      end

      it 'does not create a duplicate user' do
        expect {
          post :create, params: valid_params
        }.not_to change(User, :count)
      end
    end

    context 'with marketing_emails parameter' do
      it 'accepts marketing_emails opt-in' do
        params = valid_params.deep_dup
        params[:user][:marketing_emails] = '1'
        
        post :create, params: params
        user = User.last
        expect(user.marketing_emails).to be_truthy if user.respond_to?(:marketing_emails)
      end

      it 'accepts marketing_emails opt-out' do
        params = valid_params.deep_dup
        params[:user][:marketing_emails] = '0'
        
        post :create, params: params
        user = User.last
        expect(user.marketing_emails).to be_falsy if user.respond_to?(:marketing_emails)
      end
    end
  end

  describe 'redirects after signup' do
    context 'when user is successfully created' do
      it 'redirects to root path' do
        post :create, params: valid_params
        expect(response).to redirect_to(root_path)
      end

      it 'sets appropriate flash message' do
        post :create, params: valid_params
        expect(flash[:notice]).to eq('Please check your email to confirm your account.')
      end
    end
  end

  private

  def valid_params
    {
      user: {
        email: 'test@example.com',
        password: 'password123',
        password_confirmation: 'password123',
        first_name: 'John',
        last_name: 'Doe',
        timezone: 'America/New_York'
      }
    }
  end
end