require 'rails_helper'

RSpec.describe 'Email Confirmation Flow', type: :feature do
  let(:unconfirmed_user) { create(:user, confirmed_at: nil) }

  before do
    ActionMailer::Base.deliveries.clear
  end

  describe 'confirmation email sending' do
    it 'sends confirmation email when user signs up' do
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
      expect(confirmation_email.subject).to match(/confirm/i)
      expect(confirmation_email.body.encoded).to include('confirm')
    end

    it 'allows resending confirmation email' do
      visit new_user_confirmation_path

      fill_in 'Email', with: unconfirmed_user.email

      expect {
        click_button 'Resend confirmation instructions'
      }.to change { ActionMailer::Base.deliveries.count }.by(1)

      confirmation_email = ActionMailer::Base.deliveries.last
      expect(confirmation_email.to).to include(unconfirmed_user.email)
    end
  end

  describe 'email confirmation process' do
    it 'confirms user account when clicking confirmation link' do
      # Generate confirmation token
      unconfirmed_user.send_confirmation_instructions

      # Extract confirmation token from the email
      confirmation_email = ActionMailer::Base.deliveries.last
      email_body = confirmation_email.body.encoded
      
      # Extract token from confirmation URL in email
      match = email_body.match(/confirmation_token=([^&"'\s]+)/)
      expect(match).to be_present, "Confirmation token not found in email body"
      
      confirmation_token = match[1]

      # Visit confirmation URL
      visit user_confirmation_path(confirmation_token: confirmation_token)

      expect(page).to have_content('Your email address has been successfully confirmed')
      
      # User should now be confirmed
      unconfirmed_user.reload
      expect(unconfirmed_user.confirmed_at).to be_present
      expect(unconfirmed_user).to be_confirmed
    end

    it 'shows error for invalid confirmation token' do
      visit user_confirmation_path(confirmation_token: 'invalid-token')

      expect(page).to have_content('Confirmation token is invalid')
    end

    it 'shows error for expired confirmation token' do
      # Create user with expired confirmation sent time
      unconfirmed_user.update(confirmation_sent_at: 3.days.ago)
      unconfirmed_user.send_confirmation_instructions

      # Extract token
      confirmation_email = ActionMailer::Base.deliveries.last
      email_body = confirmation_email.body.encoded
      match = email_body.match(/confirmation_token=([^&"'\s]+)/)
      confirmation_token = match[1]

      # Simulate token expiration by manipulating the sent time
      unconfirmed_user.update(confirmation_sent_at: 1.week.ago)

      visit user_confirmation_path(confirmation_token: confirmation_token)

      expect(page).to have_content('needs to be confirmed within')
    end
  end

  describe 'post-confirmation behavior' do
    let(:newly_confirmed_user) { create(:user, confirmed_at: nil) }

    it 'sends welcome email after confirmation' do
      # Mock the confirmation process
      expect(UserMailer).to receive(:welcome_email).with(newly_confirmed_user).and_call_original
      expect_any_instance_of(ActionMailer::MessageDelivery).to receive(:deliver_now)

      newly_confirmed_user.confirm
    end

    it 'redirects to sign in after confirmation' do
      newly_confirmed_user.send_confirmation_instructions
      
      confirmation_email = ActionMailer::Base.deliveries.last
      email_body = confirmation_email.body.encoded
      match = email_body.match(/confirmation_token=([^&"'\s]+)/)
      confirmation_token = match[1]

      visit user_confirmation_path(confirmation_token: confirmation_token)

      expect(page).to have_content('Your email address has been successfully confirmed')
      # Check that we're redirected to sign in or appropriate page
      expect(current_path).to eq(new_user_session_path).or eq(root_path)
    end

    it 'allows confirmed user to sign in' do
      confirmed_user = create(:user, confirmed_at: 1.day.ago)

      visit new_user_session_path
      
      fill_in 'Email', with: confirmed_user.email
      fill_in 'Password', with: 'password123'
      
      click_button 'Log in'

      expect(page).to have_content('Signed in successfully')
      expect(current_path).to eq(dashboard_path)
    end
  end

  describe 'confirmation page' do
    it 'displays resend confirmation form' do
      visit new_user_confirmation_path

      expect(page).to have_field('Email')
      expect(page).to have_button('Resend confirmation instructions')
      expect(page).to have_content('Resend confirmation instructions')
    end

    it 'has link back to sign in' do
      visit new_user_confirmation_path

      expect(page).to have_link('Sign in', href: new_user_session_path)
    end

    it 'validates email field on resend' do
      visit new_user_confirmation_path

      fill_in 'Email', with: 'nonexistent@example.com'
      click_button 'Resend confirmation instructions'

      expect(page).to have_content('Email not found')
    end
  end

  describe 'user state management' do
    it 'prevents unconfirmed user from signing in' do
      visit new_user_session_path
      
      fill_in 'Email', with: unconfirmed_user.email
      fill_in 'Password', with: 'password123'
      
      click_button 'Log in'

      expect(page).to have_content('You have to confirm your email address before continuing')
      expect(current_path).to eq(new_user_session_path)
    end

    it 'shows appropriate subscription status for confirmed user without subscription' do
      confirmed_user = create(:user, confirmed_at: 1.day.ago)
      
      # Sign in as confirmed user
      visit new_user_session_path
      fill_in 'Email', with: confirmed_user.email
      fill_in 'Password', with: 'password123'
      click_button 'Log in'

      # Visit dashboard or subscription page
      visit dashboard_path
      
      expect(page).to have_content('No Subscription')
      expect(confirmed_user.has_active_subscription?).to be false
    end
  end

  describe 'email content validation' do
    it 'confirmation email contains proper content' do
      unconfirmed_user.send_confirmation_instructions

      confirmation_email = ActionMailer::Base.deliveries.last
      email_body = confirmation_email.body.encoded

      expect(email_body).to include(unconfirmed_user.first_name)
      expect(email_body).to include('confirm')
      expect(email_body).to include('confirmation')
      expect(email_body).to match(/https?:\/\/.*confirmation_token=/)
    end

    it 'welcome email is sent after confirmation' do
      # Clear any existing emails
      ActionMailer::Base.deliveries.clear

      # Confirm the user (this should trigger welcome email)
      unconfirmed_user.update!(confirmed_at: Time.current)

      # Check welcome email was sent
      expect(ActionMailer::Base.deliveries.count).to eq(1)
      welcome_email = ActionMailer::Base.deliveries.last
      expect(welcome_email.to).to include(unconfirmed_user.email)
      expect(welcome_email.subject).to match(/welcome/i)
    end
  end

  describe 'edge cases' do
    it 'handles already confirmed user gracefully' do
      confirmed_user = create(:user, confirmed_at: 1.day.ago)

      visit new_user_confirmation_path
      fill_in 'Email', with: confirmed_user.email
      click_button 'Resend confirmation instructions'

      expect(page).to have_content('was already confirmed')
    end

    it 'handles multiple confirmation attempts' do
      # Send confirmation multiple times
      unconfirmed_user.send_confirmation_instructions
      first_email = ActionMailer::Base.deliveries.last
      
      unconfirmed_user.send_confirmation_instructions  
      second_email = ActionMailer::Base.deliveries.last

      # Both emails should work for confirmation
      expect(ActionMailer::Base.deliveries.count).to eq(2)
      expect(second_email.to).to include(unconfirmed_user.email)
    end
  end
end