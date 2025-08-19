class ApplicationMailer < ActionMailer::Base
  default from: ENV['DEFAULT_FROM_EMAIL'] || 'noreply@example.com'
  layout 'mailer'
  
  protected
  
  def application_name
    Rails.application.class.module_parent_name
  end
  
  def support_email
    ENV['SUPPORT_EMAIL'] || 'support@example.com'
  end
  
  def company_address
    "123 Main Street, Suite 100<br>San Francisco, CA 94102"
  end
end
