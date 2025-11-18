# Controller for QuickBooks Online Single Sign-On (SSO) authentication
# Handles user signup and login via QBO OpenID Connect
class Auth::QboSsoController < ApplicationController
  # Skip authentication - this IS the authentication
  skip_before_action :authenticate_user!, only: [:connect, :callback, :complete]

  # Initiate QBO SSO flow
  # Works for both new signups and returning users
  def connect
    # Generate and store state parameter for CSRF protection
    state = SecureRandom.hex(32)
    session[:qbo_sso_state] = state

    redirect_to qbo_authorization_url(state), allow_other_host: true
  end

  # Handle OAuth callback from QuickBooks
  # Security: Implements 302 redirect pattern per Intuit requirements
  # Stores sensitive parameters in session and redirects to prevent token leakage via Referer header
  def callback
    # Store OAuth parameters in session (encrypted by Rails)
    # IMPORTANT: Use string keys - session serialization converts symbol keys to strings
    session[:qbo_sso_callback_params] = {
      'code' => params[:code],
      'state' => params[:state],
      'realm_id' => params[:realmId]
    }

    # Immediately issue 302 redirect to clean URL (no sensitive data in URL)
    # This prevents tokens from leaking via Referer header
    redirect_to auth_qbo_sso_complete_path, status: :found  # 302 Found
  end

  # Complete the OAuth callback after 302 redirect
  # This action has a clean URL with no sensitive parameters
  def complete
    begin
      # Retrieve OAuth parameters from session
      callback_params = session.delete(:qbo_sso_callback_params)

      unless callback_params
        Rails.logger.error "QBO SSO: No callback params in session"
        redirect_to new_user_session_path, alert: 'Authentication session expired. Please try again.'
        return
      end

      # Validate state parameter for CSRF protection
      # Use string keys - session serialization converts symbol keys to strings
      unless callback_params['state'].present? && callback_params['state'] == session[:qbo_sso_state]
        Rails.logger.error "QBO SSO state mismatch: expected #{session[:qbo_sso_state]}, got #{callback_params['state']}"
        redirect_to new_user_session_path, alert: 'Authentication failed. Please try again.'
        return
      end

      # Clear state from session after validation
      session.delete(:qbo_sso_state)

      # Exchange authorization code for tokens
      token_response = exchange_code_for_tokens(callback_params['code'])

      # Validate ID token (OpenID Connect requirement)
      unless QboService.validate_id_token(qbo_client, token_response[:id_token])
        Rails.logger.error "QBO SSO: ID token validation failed"
        redirect_to new_user_session_path, alert: 'Failed to validate QuickBooks identity. Please try again.'
        return
      end

      # Fetch user profile info from Intuit
      user_info = QboService.fetch_user_info(qbo_client, token_response[:access_token])

      unless user_info
        redirect_to new_user_session_path, alert: 'Failed to retrieve user information from QuickBooks. Please try again.'
        return
      end

      # CRITICAL: Verify email is verified (per Intuit documentation requirement)
      unless user_info[:email_verified]
        Rails.logger.warn "QBO SSO: Email not verified for sub #{user_info[:sub]}"
        render :email_not_verified, status: :forbidden
        return
      end

      # Find or create user (handles both new and returning users)
      user = QboSsoService.find_or_create_user(
        user_info: user_info,
        token_response: token_response,
        realm_id: callback_params['realm_id']
      )

      if user.persisted?
        # Sign in user
        sign_in(user)

        Rails.logger.info "QBO SSO: User signed in - user_id: #{user.id}, sub: #{user_info[:sub]}"

        redirect_to dashboard_path, notice: 'Successfully signed in with QuickBooks!'
      else
        # User creation failed - show errors
        Rails.logger.error "QBO SSO: User creation failed - #{user.errors.full_messages.join(', ')}"
        redirect_to new_user_session_path,
                    alert: "Failed to create account: #{user.errors.full_messages.join(', ')}"
      end

    rescue IntuitOAuth::OAuth2ClientException => e
      Rails.logger.error "QBO SSO OAuth error: #{e.message}, intuit_tid: #{e.intuit_tid}"
      redirect_to new_user_session_path, alert: 'Failed to authenticate with QuickBooks. Please try again.'
    rescue => e
      Rails.logger.error "QBO SSO error: #{e.message}\n#{e.backtrace.first(5).join("\n")}"
      redirect_to new_user_session_path, alert: 'Authentication failed. Please try again.'
    end
  end

  private

  # Initialize QBO OAuth client with SSO callback URL
  def qbo_client
    @qbo_client ||= IntuitOAuth::Client.new(
      ENV['QBO_CLIENT_ID'],
      ENV['QBO_CLIENT_SECRET'],
      auth_qbo_sso_callback_url, # Different callback URL from API linking
      ENV['QBO_ENVIRONMENT'] || 'sandbox'
    )
  end

  # Generate QBO authorization URL with OpenID scopes
  def qbo_authorization_url(state)
    # Request OpenID Connect scopes for SSO along with accounting access
    scopes = [
      IntuitOAuth::Scopes::ACCOUNTING,
      IntuitOAuth::Scopes::OPENID,
      IntuitOAuth::Scopes::PROFILE,
      IntuitOAuth::Scopes::EMAIL
    ]

    # Get the SDK-generated URL
    auth_url = qbo_client.code.get_auth_uri(scopes)

    # Replace SDK's state parameter with our own for session tracking
    uri = URI.parse(auth_url)
    params = Rack::Utils.parse_query(uri.query)
    params['state'] = state
    uri.query = params.to_query

    uri.to_s
  end

  # Exchange authorization code for access and ID tokens
  def exchange_code_for_tokens(code)
    token_response = qbo_client.token.get_bearer_token(code)

    {
      access_token: token_response.access_token,
      refresh_token: token_response.refresh_token,
      expires_in: token_response.expires_in,
      id_token: token_response.id_token
    }
  end
end
