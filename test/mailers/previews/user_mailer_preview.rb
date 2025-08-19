class UserMailerPreview < ActionMailer::Preview
  def welcome_email
    user = User.first || create_sample_user
    UserMailer.welcome_email(user)
  end
  
  def confirmation_instructions
    user = User.first || create_sample_user
    token = 'sample_confirmation_token'
    UserMailer.confirmation_instructions(user, token)
  end
  
  def reset_password_instructions
    user = User.first || create_sample_user
    token = 'sample_reset_token'
    UserMailer.reset_password_instructions(user, token)
  end
  
  def email_changed
    user = User.first || create_sample_user
    UserMailer.email_changed(user)
  end
  
  def account_deleted
    user_data = {
      name: 'John Doe',
      email: 'john@example.com',
      deleted_at: Time.current
    }
    UserMailer.account_deleted(user_data)
  end
  
  def subscription_updated
    user = User.first || create_sample_user
    UserMailer.subscription_updated(user, 'free', 'standard')
  end
  
  def payment_failed
    user = User.first || create_sample_user
    invoice_url = 'https://invoice.stripe.com/sample'
    UserMailer.payment_failed(user, invoice_url)
  end
  
  def trial_ending_reminder
    user = User.first || create_sample_user
    UserMailer.trial_ending_reminder(user, 3)
  end
  
  def data_export_ready
    user = User.first || create_sample_user
    file_path = Rails.root.join('tmp', 'exports', 'sample_export.json').to_s
    UserMailer.data_export_ready(user, file_path)
  end
  
  private
  
  def create_sample_user
    User.new(
      id: 1,
      email: 'preview@example.com',
      first_name: 'John',
      last_name: 'Doe',
      timezone: 'UTC',
      created_at: 1.month.ago,
      confirmed_at: 1.month.ago
    )
  end
end