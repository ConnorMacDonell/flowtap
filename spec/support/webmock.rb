require 'webmock/rspec'

# Allow connections to localhost for test server
WebMock.disable_net_connect!(allow_localhost: true)

RSpec.configure do |config|
  config.before(:each) do
    # Reset WebMock before each test
    WebMock.reset!

    # Stub SendGrid API calls
    stub_request(:post, "https://api.sendgrid.com/v3/mail/send")
      .to_return(status: 202, body: "", headers: {})
  end

  config.before(:each, type: :feature) do
    # Mock Stripe Customer creation for feature tests
    allow(Stripe::Customer).to receive(:create).and_return(
      double('Stripe::Customer', id: 'cus_test123', email: 'test@example.com')
    )

    # Mock Stripe Checkout Session creation for feature tests
    allow(Stripe::Checkout::Session).to receive(:create).and_return(
      double('Stripe::Checkout::Session', id: 'cs_test123', url: 'https://checkout.stripe.com/test')
    )

    # Mock Stripe Subscription retrieval for feature tests
    allow(Stripe::Subscription).to receive(:retrieve).and_return(
      double('Stripe::Subscription', id: 'sub_test123', status: 'active', cancel_at_period_end: false)
    )

    # Mock Stripe Subscription update/cancel for feature tests
    allow(Stripe::Subscription).to receive(:update).and_return(
      double('Stripe::Subscription', id: 'sub_test123', status: 'canceled', cancel_at_period_end: true)
    )
  end
end
