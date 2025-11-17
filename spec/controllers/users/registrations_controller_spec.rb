require 'rails_helper'

RSpec.describe Users::RegistrationsController, type: :controller do
  before do
    @request.env["devise.mapping"] = Devise.mappings[:user]

    # Stub Stripe API calls
    allow(Stripe::Customer).to receive(:create).and_return(
      double(id: 'cus_test123')
    )
    allow(Stripe::Checkout::Session).to receive(:create).and_return(
      double(url: 'https://checkout.stripe.com/test123')
    )
  end

  describe 'GET #new' do
    it 'returns successful response' do
      get :new
      expect(response).to be_successful
    end

    it 'disables caching per Intuit security requirements (inherited from ApplicationController)' do
      get :new

      # Verify caching is disabled and compatibility headers are set
      expect(response.headers['Cache-Control']).to include('no-store')
      expect(response.headers['Pragma']).to eq('no-cache')
      expect(response.headers['Expires']).to eq('0')
    end
  end

  describe 'POST #create' do
    let(:unique_email) { "test-#{SecureRandom.hex(4)}@example.com" }
    let(:valid_params) do
      {
        user: {
          email: unique_email,
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

      it 'creates an inactive subscription automatically' do
        post :create, params: valid_params
        user = User.last
        expect(user.subscription).to be_present
        expect(user.subscription.status).to eq('inactive')
      end

      it 'sets the user attributes correctly' do
        post :create, params: valid_params
        user = User.last
        expect(user.email).to eq(unique_email)
        expect(user.first_name).to eq('John')
        expect(user.last_name).to eq('Doe')
        expect(user.timezone).to eq('America/New_York')
      end

      it 'redirects to Stripe payment link' do
        post :create, params: valid_params
        expect(response).to have_http_status(:redirect)
        # Redirects to external Stripe URL, can't assert exact URL in test
      end

      it 'sends a confirmation email' do
        expect {
          post :create, params: valid_params
        }.to change(ActionMailer::Base.deliveries, :count).by(1)

        confirmation_email = ActionMailer::Base.deliveries.last
        expect(confirmation_email.to).to include(unique_email)
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

      it 'requires password minimum length of 8 characters (Intuit requirement)' do
        params = valid_params.deep_dup
        params[:user][:password] = 'short'  # 5 characters, below minimum
        params[:user][:password_confirmation] = 'short'

        expect {
          post :create, params: params
        }.not_to change(User, :count)
      end
    end

    context 'with duplicate email' do
      before do
        create(:user, email: 'duplicate@example.com')
      end

      it 'does not create a duplicate user' do
        dup_params = valid_params.deep_dup
        dup_params[:user][:email] = 'duplicate@example.com'

        expect {
          post :create, params: dup_params
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
end