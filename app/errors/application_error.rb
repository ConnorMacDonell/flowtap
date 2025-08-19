class ApplicationError < StandardError
  attr_reader :user_message, :error_code
  
  def initialize(message, user_message: nil, error_code: nil)
    super(message)
    @user_message = user_message || "An unexpected error occurred. Please try again."
    @error_code = error_code
  end
end

class SubscriptionError < ApplicationError
  def initialize(message, user_message: nil)
    super(message, user_message: user_message || "There was a problem with your subscription.", error_code: 'SUBSCRIPTION_ERROR')
  end
end

class PaymentError < ApplicationError
  def initialize(message, user_message: nil)
    super(message, user_message: user_message || "Payment processing failed. Please check your payment method.", error_code: 'PAYMENT_ERROR')
  end
end

class ExportError < ApplicationError
  def initialize(message, user_message: nil)
    super(message, user_message: user_message || "Data export failed. Please try again later.", error_code: 'EXPORT_ERROR')
  end
end

class EmailError < ApplicationError
  def initialize(message, user_message: nil)
    super(message, user_message: user_message || "Email delivery failed. Please check your email address.", error_code: 'EMAIL_ERROR')
  end
end