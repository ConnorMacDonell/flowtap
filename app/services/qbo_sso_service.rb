# Service for handling QuickBooks Online SSO user creation and authentication
class QboSsoService
  class << self
    # Find or create user from QBO OpenID Connect data
    # @param user_info [Hash] OpenID user info (sub, email, given_name, family_name, email_verified)
    # @param token_response [Hash] OAuth token response (access_token, refresh_token, expires_in, id_token)
    # @param realm_id [String] QBO company realm ID
    # @return [User] The found or created user
    def find_or_create_user(user_info:, token_response:, realm_id:)
      # Try to find existing user by QBO sub (unique identifier)
      user = User.find_by(qbo_sub_id: user_info[:sub])

      if user.present?
        # Existing QBO SSO user - update tokens and profile
        update_user_tokens(user, user_info, token_response, realm_id)
        return user
      end

      # Check if email already exists (existing email/password account)
      user = User.find_by(email: user_info[:email])

      if user.present?
        # Email exists - link QBO SSO to existing account
        link_qbo_to_existing_user(user, user_info, token_response, realm_id)
        return user
      end

      # Create new user from QBO SSO
      create_user_from_qbo(user_info, token_response, realm_id)
    end

    private

    # Update existing QBO SSO user's tokens and profile
    def update_user_tokens(user, user_info, token_response, realm_id)
      user.update!(
        # OAuth tokens
        qbo_access_token: token_response[:access_token],
        qbo_refresh_token: token_response[:refresh_token],
        qbo_token_expires_at: Time.current + token_response[:expires_in].seconds,
        qbo_id_token: token_response[:id_token],
        qbo_realm_id: realm_id,
        qbo_connected_at: Time.current,

        # Update profile info in case it changed
        qbo_user_email: user_info[:email],
        qbo_user_email_verified: user_info[:email_verified],
        qbo_user_given_name: user_info[:given_name],
        qbo_user_family_name: user_info[:family_name]
      )

      Rails.logger.info("QBO SSO: Updated tokens for existing user #{user.id} (sub: #{user_info[:sub]})")
    end

    # Link QBO SSO to existing email/password account
    def link_qbo_to_existing_user(user, user_info, token_response, realm_id)
      user.update!(
        # QBO OpenID fields
        qbo_sub_id: user_info[:sub],
        qbo_user_email: user_info[:email],
        qbo_user_email_verified: user_info[:email_verified],
        qbo_user_given_name: user_info[:given_name],
        qbo_user_family_name: user_info[:family_name],

        # OAuth tokens
        qbo_access_token: token_response[:access_token],
        qbo_refresh_token: token_response[:refresh_token],
        qbo_token_expires_at: Time.current + token_response[:expires_in].seconds,
        qbo_id_token: token_response[:id_token],
        qbo_realm_id: realm_id,
        qbo_connected_at: Time.current
      )

      Rails.logger.info("QBO SSO: Linked QBO to existing user #{user.id} (sub: #{user_info[:sub]})")
    end

    # Create new user from QBO SSO
    def create_user_from_qbo(user_info, token_response, realm_id)
      user = User.create!(
        # User account fields
        email: user_info[:email],
        first_name: user_info[:given_name] || 'QuickBooks',
        last_name: user_info[:family_name] || 'User',
        password: Devise.friendly_token[0, 20], # Random password (not used for SSO)
        confirmed_at: Time.current, # Auto-confirm (email verified by Intuit)
        timezone: 'UTC', # Default timezone

        # EULA acceptance (implicit consent via "By creating account..." message)
        eula_accepted_at: Time.current,
        privacy_policy_accepted_at: Time.current,

        # QBO OpenID fields
        qbo_sub_id: user_info[:sub],
        qbo_user_email: user_info[:email],
        qbo_user_email_verified: user_info[:email_verified],
        qbo_user_given_name: user_info[:given_name],
        qbo_user_family_name: user_info[:family_name],

        # QBO OAuth tokens
        qbo_access_token: token_response[:access_token],
        qbo_refresh_token: token_response[:refresh_token],
        qbo_token_expires_at: Time.current + token_response[:expires_in].seconds,
        qbo_id_token: token_response[:id_token],
        qbo_realm_id: realm_id,
        qbo_connected_at: Time.current
      )

      Rails.logger.info("QBO SSO: Created new user #{user.id} from QBO (sub: #{user_info[:sub]})")

      # Create audit log for compliance
      AuditLog.create(
        user_id: user.id,
        action: 'qbo_sso_signup',
        metadata: {
          qbo_sub: user_info[:sub],
          qbo_email: user_info[:email],
          signup_method: 'qbo_sso'
        }
      )

      user
    rescue ActiveRecord::RecordInvalid => e
      Rails.logger.error("QBO SSO: Failed to create user - #{e.message}")
      # Return unsaved user with errors for display
      User.new.tap { |u| u.errors.add(:base, e.message) }
    end
  end
end
