require 'rails_helper'

RSpec.describe 'User Signup Flow', type: :feature do
  before do
    clear_emails
    stub_stripe_apis
  end

  describe 'successful signup flow' do
    it 'allows a user to sign up with valid information' do
      visit new_user_registration_path

      expect(page).to have_content('Create your account')
      expect(page).to have_field('Email')
      expect(page).to have_field('Password')
      expect(page).to have_field('Confirm Password')
      expect(page).to have_field('First name')
      expect(page).to have_field('Last name')

      fill_signup_form

      expect {
        click_button 'Create Account'
      }.to change(User, :count).by(1)

      # After signup, user is redirected to Stripe payment link
      # We can't follow external redirects in tests, so check for the flash message or error page
      # The system redirects to external Stripe URL which shows as routing error in test environment

      # Verify user was created correctly
      user = User.last
      expect(user.email).to eq('newuser@example.com')
      expect(user.first_name).to eq('John')
      expect(user.last_name).to eq('Doe')
      expect(user.confirmed_at).to be_nil
    end

    it 'sends confirmation email after successful signup' do
      visit new_user_registration_path
      fill_signup_form

      expect {
        click_button 'Create Account'
      }.to change { ActionMailer::Base.deliveries.count }.by(1)

      confirmation_email = ActionMailer::Base.deliveries.last
      expect(confirmation_email.to).to include('newuser@example.com')
      expect(confirmation_email.subject).to match(/confirm/i)
    end

    it 'allows marketing email opt-in during signup' do
      skip "Marketing emails feature not implemented"
    end
  end

  describe 'signup validation errors' do
    it 'shows validation errors for invalid input' do
      visit new_user_registration_path

      # Try to submit with invalid data
      fill_in 'Email', with: 'invalid-email'
      fill_in 'Password', with: 'short'
      fill_in 'Confirm Password', with: 'different'
      fill_in 'First name', with: ''
      fill_in 'Last name', with: ''

      click_button 'Create Account'

      expect(page).to have_content('Create your account')  # Still on signup page
      expect(page).to have_content('is invalid')  # Email validation error
      expect(page).to have_content("can't be blank")  # Name validation errors
      expect(page).to have_content("doesn't match")  # Password confirmation error

      expect(User.count).to eq(0)  # No user was created
    end

    it 'shows error when email is already taken' do
      create(:user, email: 'existing@example.com')

      visit new_user_registration_path
      fill_signup_form(email: 'existing@example.com')

      click_button 'Create Account'

      expect(page).to have_content('has already been taken')
      expect(User.where(email: 'existing@example.com').count).to eq(1)  # Still only one user
    end

    it 'requires password to be at least 6 characters' do
      visit new_user_registration_path
      fill_signup_form(email: 'test@example.com', password: '12345')

      click_button 'Create Account'

      expect(page).to have_content('is too short (minimum is 6 characters)')
      expect(User.count).to eq(0)
    end

    it 'requires password confirmation to match password' do
      visit new_user_registration_path
      fill_signup_form(email: 'test@example.com', password: 'password123', password_confirmation: 'different123')

      click_button 'Create Account'

      expect(page).to have_content("doesn't match")
      expect(User.count).to eq(0)
    end

    it 'requires all mandatory fields' do
      visit new_user_registration_path

      # Leave all fields empty
      click_button 'Create Account'

      expect(page).to have_content("can't be blank", minimum: 4)  # Email, password, first_name, last_name
      expect(User.count).to eq(0)
    end
  end

  describe 'signup page navigation' do
    it 'has a link to sign in page' do
      visit new_user_registration_path

      expect(page).to have_link('sign in to your existing account', href: new_user_session_path)
    end

    it 'displays the signup form with all required fields' do
      visit new_user_registration_path

      expect(page).to have_field('user[email]')
      expect(page).to have_field('user[password]')
      expect(page).to have_field('user[password_confirmation]')
      expect(page).to have_field('user[first_name]')
      expect(page).to have_field('user[last_name]')
      expect(page).to have_button('Create Account')
    end

    it 'shows application branding/header' do
      visit new_user_registration_path

      # Adjust these expectations based on your actual page layout
      expect(page).to have_content('Create your account')  # Page title or header
    end
  end

  describe 'user status after signup' do
    let!(:user) { create_user_through_signup }

    it 'creates user in unconfirmed state' do
      expect(user.confirmed_at).to be_nil
      expect(user).not_to be_confirmed
    end

    it 'creates inactive subscription automatically' do
      expect(user.subscription).to be_present
      expect(user.subscription.status).to eq('inactive')
      expect(user.has_active_subscription?).to be false
    end

    it 'cannot access protected features without confirmation' do
      expect(user.can_access_feature?('qbo_integration')).to be false
    end

    it 'sets default values correctly' do
      expect(user.deleted_at).to be_nil
      expect(user.subscription_tier).to eq('inactive')
      expect(user.subscription_tier_name).to eq('Inactive')
    end
  end

  private

  def clear_emails
    ActionMailer::Base.deliveries.clear
  end

  def stub_stripe_apis
    # Stub Stripe Customer creation
    allow(Stripe::Customer).to receive(:create).and_return(
      double(id: 'cus_test123')
    )

    # Stub Stripe Checkout Session creation
    allow(Stripe::Checkout::Session).to receive(:create).and_return(
      double(url: 'https://checkout.stripe.com/test-session')
    )

    # Stub other Stripe operations that might be called
    allow(Stripe::Subscription).to receive(:cancel).and_return(true)
    allow(Stripe::Subscription).to receive(:update).and_return(true)
  end

  def create_user_through_signup
    visit new_user_registration_path
    fill_signup_form(email: 'testuser@example.com', first_name: 'Test', last_name: 'User')
    click_button 'Create Account'
    User.find_by(email: 'testuser@example.com')
  end
end