if Rails.env.production?
  ActionMailer::Base.smtp_settings = {
    user_name: 'apikey',
    password: ENV['SENDGRID_API_KEY'],
    domain: ENV['APPLICATION_HOST'] || 'localhost:3000',
    address: 'smtp.sendgrid.net',
    port: 587,
    authentication: :plain,
    enable_starttls_auto: true
  }

  ActionMailer::Base.delivery_method = :smtp
elsif Rails.env.development?
  ActionMailer::Base.delivery_method = :letter_opener
  ActionMailer::Base.perform_deliveries = true
elsif Rails.env.test?
  ActionMailer::Base.delivery_method = :test
  ActionMailer::Base.perform_deliveries = true
end

ActionMailer::Base.default_url_options = {
  host: ENV['APPLICATION_HOST'] || 'localhost:3000',
  protocol: Rails.env.production? ? 'https' : 'http'
}