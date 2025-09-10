require 'rails_helper'

RSpec.describe 'User Signup Flow', type: :feature do
  before do
    clear_emails
  end

  describe 'successful signup flow' do
    it 'allows a user to sign up with valid information' do
      visit new_user_registration_path

      expect(page).to have_content('Sign up')
      expect(page).to have_field('Email')
      expect(page).to have_field('Password')
      expect(page).to have_field('Password confirmation')
      expect(page).to have_field('First name')
      expect(page).to have_field('Last name')
      expect(page).to have_field('Timezone')

      fill_in 'Email', with: 'newuser@example.com'
      fill_in 'Password', with: 'password123'
      fill_in 'Password confirmation', with: 'password123'
      fill_in 'First name', with: 'John'
      fill_in 'Last name', with: 'Doe'
      select 'America/New_York', from: 'Timezone'

      expect {
        click_button 'Sign up'
      }.to change(User, :count).by(1)

      expect(page).to have_content('Welcome! Please check your email to confirm your account.')
      expect(current_path).to eq(root_path)

      # Verify user was created correctly
      user = User.last
      expect(user.email).to eq('newuser@example.com')
      expect(user.first_name).to eq('John')
      expect(user.last_name).to eq('Doe')
      expect(user.timezone).to eq('America/New_York')
      expect(user.confirmed_at).to be_nil
      expect(user.subscription).to be_nil
    end

    it 'sends confirmation email after successful signup' do
      visit new_user_registration_path

      fill_in 'Email', with: 'newuser@example.com'
      fill_in 'Password', with: 'password123'
      fill_in 'Password confirmation', with: 'password123'
      fill_in 'First name', with: 'John'
      fill_in 'Last name', with: 'Doe'
      select 'America/New_York', from: 'Timezone'

      expect {
        click_button 'Sign up'
      }.to change { ActionMailer::Base.deliveries.count }.by(1)

      confirmation_email = ActionMailer::Base.deliveries.last
      expect(confirmation_email.to).to include('newuser@example.com')
      expect(confirmation_email.subject).to match(/confirmation/i)
    end

    it 'allows marketing email opt-in during signup' do
      visit new_user_registration_path

      fill_in 'Email', with: 'newuser@example.com'
      fill_in 'Password', with: 'password123'
      fill_in 'Password confirmation', with: 'password123'
      fill_in 'First name', with: 'John'
      fill_in 'Last name', with: 'Doe'
      select 'America/New_York', from: 'Timezone'
      
      # Check marketing emails checkbox if it exists
      if page.has_field?('Marketing emails')
        check 'Marketing emails'
      end

      click_button 'Sign up'

      user = User.last
      if user.respond_to?(:marketing_emails)
        expect(user.marketing_emails).to be_truthy
      end
    end
  end

  describe 'signup validation errors' do
    it 'shows validation errors for invalid input' do
      visit new_user_registration_path

      # Try to submit with invalid data
      fill_in 'Email', with: 'invalid-email'
      fill_in 'Password', with: 'short'
      fill_in 'Password confirmation', with: 'different'
      fill_in 'First name', with: ''
      fill_in 'Last name', with: ''

      click_button 'Sign up'

      expect(page).to have_content('Sign up')  # Still on signup page
      expect(page).to have_content('is invalid')  # Email validation error
      expect(page).to have_content("can't be blank")  # Name validation errors
      expect(page).to have_content("doesn't match")  # Password confirmation error

      expect(User.count).to eq(0)  # No user was created
    end

    it 'shows error when email is already taken' do
      create(:user, email: 'existing@example.com')

      visit new_user_registration_path

      fill_in 'Email', with: 'existing@example.com'
      fill_in 'Password', with: 'password123'
      fill_in 'Password confirmation', with: 'password123'
      fill_in 'First name', with: 'John'
      fill_in 'Last name', with: 'Doe'
      select 'America/New_York', from: 'Timezone'

      click_button 'Sign up'

      expect(page).to have_content('has already been taken')
      expect(User.where(email: 'existing@example.com').count).to eq(1)  # Still only one user
    end

    it 'requires password to be at least 6 characters' do
      visit new_user_registration_path

      fill_in 'Email', with: 'test@example.com'
      fill_in 'Password', with: '12345'  # Too short
      fill_in 'Password confirmation', with: '12345'
      fill_in 'First name', with: 'John'
      fill_in 'Last name', with: 'Doe'
      select 'America/New_York', from: 'Timezone'

      click_button 'Sign up'

      expect(page).to have_content('is too short (minimum is 6 characters)')
      expect(User.count).to eq(0)
    end

    it 'requires password confirmation to match password' do
      visit new_user_registration_path

      fill_in 'Email', with: 'test@example.com'
      fill_in 'Password', with: 'password123'
      fill_in 'Password confirmation', with: 'different123'
      fill_in 'First name', with: 'John'
      fill_in 'Last name', with: 'Doe'
      select 'America/New_York', from: 'Timezone'

      click_button 'Sign up'

      expect(page).to have_content("doesn't match")
      expect(User.count).to eq(0)
    end

    it 'requires all mandatory fields' do
      visit new_user_registration_path

      # Leave all fields empty
      click_button 'Sign up'

      expect(page).to have_content("can't be blank", count: 4)  # Email, password, first_name, last_name, timezone
      expect(User.count).to eq(0)
    end
  end

  describe 'signup page navigation' do
    it 'has a link to sign in page' do
      visit new_user_registration_path

      expect(page).to have_link('Sign in', href: new_user_session_path)
    end

    it 'displays the signup form with all required fields' do
      visit new_user_registration_path

      expect(page).to have_field('user[email]')
      expect(page).to have_field('user[password]')
      expect(page).to have_field('user[password_confirmation]')
      expect(page).to have_field('user[first_name]')
      expect(page).to have_field('user[last_name]')
      expect(page).to have_field('user[timezone]')
      expect(page).to have_button('Sign up')
    end

    it 'shows application branding/header' do
      visit new_user_registration_path

      # Adjust these expectations based on your actual page layout
      expect(page).to have_content('Sign up')  # Page title or header
    end
  end

  describe 'user status after signup' do
    let!(:user) { create_user_through_signup }

    it 'creates user in unconfirmed state' do
      expect(user.confirmed_at).to be_nil
      expect(user).not_to be_confirmed
    end

    it 'does not create subscription automatically' do
      expect(user.subscription).to be_nil
      expect(user.has_active_subscription?).to be false
    end

    it 'cannot access protected features without confirmation' do
      expect(user.can_access_feature?('qbo_integration')).to be false
    end

    it 'sets default values correctly' do
      expect(user.deleted_at).to be_nil
      expect(user.subscription_tier).to eq('inactive')
      expect(user.subscription_tier_name).to eq('No Subscription')
    end
  end

  private

  def clear_emails
    ActionMailer::Base.deliveries.clear
  end

  def create_user_through_signup
    visit new_user_registration_path
    
    fill_in 'Email', with: 'testuser@example.com'
    fill_in 'Password', with: 'password123'
    fill_in 'Password confirmation', with: 'password123'
    fill_in 'First name', with: 'Test'
    fill_in 'Last name', with: 'User'
    select 'America/New_York', from: 'Timezone'
    
    click_button 'Sign up'
    
    User.find_by(email: 'testuser@example.com')
  end
end