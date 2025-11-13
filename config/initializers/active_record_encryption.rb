# frozen_string_literal: true

# Configure ActiveRecord Encryption from environment variables
# Keys are generated with: bin/rails db:encryption:init
# Store keys in .env (development) or Heroku config vars (production)

Rails.application.configure do
  config.active_record.encryption.primary_key = ENV['ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY']
  config.active_record.encryption.deterministic_key = ENV['ACTIVE_RECORD_ENCRYPTION_DETERMINISTIC_KEY']
  config.active_record.encryption.key_derivation_salt = ENV['ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT']

  # Raise error if encryption keys are missing in production
  if Rails.env.production?
    if config.active_record.encryption.primary_key.blank? ||
       config.active_record.encryption.deterministic_key.blank? ||
       config.active_record.encryption.key_derivation_salt.blank?
      raise "ActiveRecord encryption keys must be set in production environment"
    end
  end
end
