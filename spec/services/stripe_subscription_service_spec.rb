require 'rails_helper'

RSpec.describe StripeSubscriptionService, type: :service do
  let(:user) { create(:user) }
  let(:service) { described_class.new(user) }

  describe '#initialize' do
    it 'initializes with a user' do
      expect(service.user).to eq(user)
    end
  end

  describe '#create_checkout_session' do
    let(:success_url) { 'https://example.com/success' }
    let(:cancel_url) { 'https://example.com/cancel' }
    let(:stripe_customer_id) { 'cus_test123' }
    let(:checkout_url) { 'https://checkout.stripe.com/test123' }

    before do
      ENV['STRIPE_STANDARD_PRICE_ID'] = 'price_test123'
    end

    context 'when user has no Stripe customer' do
      it 'creates a Stripe customer' do
        expect(Stripe::Customer).to receive(:create).with(
          email: user.email,
          name: user.full_name,
          metadata: { user_id: user.id }
        ).and_return(double(id: stripe_customer_id))

        expect(Stripe::Checkout::Session).to receive(:create).and_return(
          double(url: checkout_url)
        )

        service.create_checkout_session(success_url: success_url, cancel_url: cancel_url)

        expect(user.reload.stripe_customer_id).to eq(stripe_customer_id)
      end
    end

    context 'when user has a Stripe customer' do
      before do
        user.update!(stripe_customer_id: stripe_customer_id)
      end

      it 'does not create a new Stripe customer' do
        expect(Stripe::Customer).not_to receive(:create)

        expect(Stripe::Checkout::Session).to receive(:create).and_return(
          double(url: checkout_url)
        )

        service.create_checkout_session(success_url: success_url, cancel_url: cancel_url)
      end
    end

    context 'when user has no subscription record' do
      let(:user) { create(:user, without_subscription: true) }

      it 'creates a subscription record' do
        allow(Stripe::Customer).to receive(:create).and_return(double(id: stripe_customer_id))
        allow(Stripe::Checkout::Session).to receive(:create).and_return(double(url: checkout_url))

        expect {
          service.create_checkout_session(success_url: success_url, cancel_url: cancel_url)
        }.to change { user.reload.subscription }.from(nil)

        expect(user.subscription.status).to eq('inactive')
      end
    end

    context 'when checkout session is created successfully' do
      before do
        user.update!(stripe_customer_id: stripe_customer_id)
        user.create_subscription!(status: 'inactive')
      end

      it 'creates a Stripe checkout session' do
        expect(Stripe::Checkout::Session).to receive(:create).with(
          customer: stripe_customer_id,
          line_items: [{
            price: ENV['STRIPE_STANDARD_PRICE_ID'],
            quantity: 1
          }],
          mode: 'subscription',
          success_url: success_url,
          cancel_url: cancel_url,
          metadata: {
            user_id: user.id
          }
        ).and_return(double(url: checkout_url))

        result = service.create_checkout_session(success_url: success_url, cancel_url: cancel_url)
        expect(result).to eq(checkout_url)
      end
    end

    context 'when Stripe API fails' do
      before do
        user.update!(stripe_customer_id: stripe_customer_id)
        user.create_subscription!(status: 'inactive')
      end

      it 'returns nil and logs the error' do
        allow(Stripe::Checkout::Session).to receive(:create).and_raise(
          Stripe::StripeError.new('API error')
        )

        expect(Rails.logger).to receive(:error).with(/Failed to create checkout session/)

        result = service.create_checkout_session(success_url: success_url, cancel_url: cancel_url)
        expect(result).to be_nil
      end
    end
  end

  describe '#cancel_subscription' do
    let(:stripe_subscription_id) { 'sub_test123' }

    context 'when user has an active subscription' do
      before do
        user.create_subscription!(
          status: 'paid',
          stripe_subscription_id: stripe_subscription_id,
          current_period_start: 1.month.ago,
          current_period_end: 1.month.from_now
        )
      end

      context 'with immediate: true (default)' do
        it 'cancels the Stripe subscription' do
          expect(Stripe::Subscription).to receive(:cancel).with(stripe_subscription_id)

          service.cancel_subscription(immediate: true)
        end

        it 'updates the local subscription record' do
          allow(Stripe::Subscription).to receive(:cancel)

          service.cancel_subscription(immediate: true)

          subscription = user.reload.subscription
          expect(subscription.status).to eq('canceled')
          expect(subscription.canceled_at).to be_present
          expect(subscription.stripe_subscription_id).to be_nil
          expect(subscription.current_period_start).to be_nil
          expect(subscription.current_period_end).to be_nil
        end

        it 'returns true on success' do
          allow(Stripe::Subscription).to receive(:cancel)

          result = service.cancel_subscription(immediate: true)
          expect(result).to be true
        end

        context 'when Stripe API fails' do
          it 'raises the error' do
            allow(Stripe::Subscription).to receive(:cancel).and_raise(
              Stripe::StripeError.new('API error')
            )

            expect {
              service.cancel_subscription(immediate: true)
            }.to raise_error(Stripe::StripeError)
          end

          it 'logs the error' do
            allow(Stripe::Subscription).to receive(:cancel).and_raise(
              Stripe::StripeError.new('API error')
            )

            expect(Rails.logger).to receive(:error).with(/Failed to cancel subscription/)

            expect {
              service.cancel_subscription(immediate: true)
            }.to raise_error(Stripe::StripeError)
          end
        end
      end

      context 'with immediate: false' do
        it 'cancels the Stripe subscription' do
          expect(Stripe::Subscription).to receive(:cancel).with(stripe_subscription_id)

          service.cancel_subscription(immediate: false)
        end

        context 'when Stripe API fails' do
          it 'returns false instead of raising' do
            allow(Stripe::Subscription).to receive(:cancel).and_raise(
              Stripe::StripeError.new('API error')
            )

            result = service.cancel_subscription(immediate: false)
            expect(result).to be false
          end

          it 'logs the error' do
            allow(Stripe::Subscription).to receive(:cancel).and_raise(
              Stripe::StripeError.new('API error')
            )

            expect(Rails.logger).to receive(:error).with(/Failed to cancel subscription/)

            service.cancel_subscription(immediate: false)
          end
        end
      end
    end

    context 'when user has no subscription' do
      let(:user) { create(:user, without_subscription: true) }

      it 'returns true without making API calls' do
        expect(Stripe::Subscription).not_to receive(:cancel)

        result = service.cancel_subscription
        expect(result).to be true
      end
    end

    context 'when user has subscription but no Stripe subscription ID' do
      before do
        user.create_subscription!(status: 'inactive')
      end

      it 'returns true without making API calls' do
        expect(Stripe::Subscription).not_to receive(:cancel)

        result = service.cancel_subscription
        expect(result).to be true
      end
    end
  end

  describe '#cancel_at_period_end' do
    let(:stripe_subscription_id) { 'sub_test123' }

    context 'when user has an active subscription' do
      before do
        user.create_subscription!(
          status: 'paid',
          stripe_subscription_id: stripe_subscription_id
        )
      end

      it 'updates Stripe subscription to cancel at period end' do
        expect(Stripe::Subscription).to receive(:update).with(
          stripe_subscription_id,
          cancel_at_period_end: true
        )

        service.cancel_at_period_end
      end

      it 'updates the local subscription canceled_at timestamp' do
        allow(Stripe::Subscription).to receive(:update)

        service.cancel_at_period_end

        expect(user.reload.subscription.canceled_at).to be_present
      end

      it 'returns true on success' do
        allow(Stripe::Subscription).to receive(:update)

        result = service.cancel_at_period_end
        expect(result).to be true
      end

      context 'when Stripe API fails' do
        it 'returns false and logs the error' do
          allow(Stripe::Subscription).to receive(:update).and_raise(
            Stripe::StripeError.new('API error')
          )

          expect(Rails.logger).to receive(:error).with(/Failed to cancel subscription at period end/)

          result = service.cancel_at_period_end
          expect(result).to be false
        end
      end
    end

    context 'when user has no subscription' do
      let(:user) { create(:user, without_subscription: true) }

      it 'returns true without making API calls' do
        expect(Stripe::Subscription).not_to receive(:update)

        result = service.cancel_at_period_end
        expect(result).to be true
      end
    end
  end

  describe '#reactivate_subscription' do
    let(:stripe_subscription_id) { 'sub_test123' }

    context 'when user has a subscription set to cancel at period end' do
      before do
        user.create_subscription!(
          status: 'paid',
          stripe_subscription_id: stripe_subscription_id,
          canceled_at: 1.day.ago
        )
      end

      it 'updates Stripe subscription to not cancel at period end' do
        expect(Stripe::Subscription).to receive(:update).with(
          stripe_subscription_id,
          cancel_at_period_end: false
        )

        service.reactivate_subscription
      end

      it 'clears the local subscription canceled_at timestamp' do
        allow(Stripe::Subscription).to receive(:update)

        service.reactivate_subscription

        expect(user.reload.subscription.canceled_at).to be_nil
      end

      it 'returns true on success' do
        allow(Stripe::Subscription).to receive(:update)

        result = service.reactivate_subscription
        expect(result).to be true
      end

      context 'when Stripe API fails' do
        it 'returns false and logs the error' do
          allow(Stripe::Subscription).to receive(:update).and_raise(
            Stripe::StripeError.new('API error')
          )

          expect(Rails.logger).to receive(:error).with(/Failed to reactivate subscription/)

          result = service.reactivate_subscription
          expect(result).to be false
        end
      end
    end

    context 'when user has no subscription' do
      let(:user) { create(:user, without_subscription: true) }

      it 'returns false without making API calls' do
        expect(Stripe::Subscription).not_to receive(:update)

        result = service.reactivate_subscription
        expect(result).to be false
      end
    end
  end
end
