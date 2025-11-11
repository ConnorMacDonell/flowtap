module FeatureHelpers
  def fill_signup_form(email: 'newuser@example.com', password: 'password123',
                       password_confirmation: nil, first_name: 'John', last_name: 'Doe',
                       accept_terms: true)
    fill_in 'First name', with: first_name if first_name
    fill_in 'Last name', with: last_name if last_name
    fill_in 'Email', with: email if email
    fill_in 'Password', with: password if password
    fill_in 'Confirm Password', with: (password_confirmation || password) if password
    check 'terms_accepted' if accept_terms && has_field?('terms_accepted')
  end
end

RSpec.configure do |config|
  config.include FeatureHelpers, type: :feature
end
