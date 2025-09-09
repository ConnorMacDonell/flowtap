require 'rails_helper'

RSpec.feature 'QuickBooks Online Integration', type: :feature do
  let(:user) { create(:user) }

  before do
    login_as(user, scope: :user)
    ENV['QBO_CLIENT_ID'] = 'test_client_id'
    ENV['QBO_CLIENT_SECRET'] = 'test_client_secret'
  end

  scenario 'User with QBO connection can use QBO services' do
    # Simulate a user with QBO connection (bypass OAuth flow for simplicity)
    user.update!(
      qbo_realm_id: 'test_realm',
      qbo_access_token: 'test_token',
      qbo_token_expires_at: 1.hour.from_now,
      qbo_connected_at: Time.current
    )

    # Mock QBO API for service testing
    mock_qbo_api = instance_double(QboApi)
    allow(QboApi).to receive(:new).and_return(mock_qbo_api)
    allow(QboApi).to receive(:production=)
    allow(mock_qbo_api).to receive(:get).with(:companyinfo, 1).and_return({ 'Id' => '1' })

    # Test QBO service functionality
    qbo_service = QboService.new(user)
    expect(qbo_service.test_connection).to be true
    
    # Verify user connection state
    expect(user.qbo_connected?).to be true
    expect(user.qbo_token_valid?).to be true
  end


  scenario 'QBO status endpoint returns correct information' do
    # Without connection
    visit '/auth/qbo/status'
    expect(page).to have_content('"connected":false')
    expect(page).to have_content('"valid":false')

    # With connection
    user.update(
      qbo_realm_id: 'test_realm',
      qbo_access_token: 'test_token',
      qbo_token_expires_at: 1.hour.from_now,
      qbo_connected_at: Time.current
    )

    visit '/auth/qbo/status'
    expect(page).to have_content('"connected":true')
    expect(page).to have_content('"valid":true')
    expect(page).to have_content('"realm_id":"test_realm"')
  end
end