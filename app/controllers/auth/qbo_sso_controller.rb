# Controller for QuickBooks Online Single Sign-On (SSO) authentication
# Handles user signup and login via QBO OpenID Connect
class Auth::QboSsoController < ApplicationController
  # Skip authentication - this IS the authentication
  skip_before_action :authenticate_user!, only: [:connect, :callback]

  # Initiate QBO SSO flow
  # Works for both new signups and returning users
  def connect
    # Generate and store state parameter for CSRF protection
    state = SecureRandom.hex(32)
    session[:qbo_sso_state] = state

    redirect_to qbo_authorization_url(state), allow_other_host: true
  end

  # Handle OAuth callback from QuickBooks
  # Creates or logs in user based on QBO OpenID data
  def callback
    begin
      # Validate state parameter for CSRF protection
      unless params[:state].present? && params[:state] == session[:qbo_sso_state]
        Rails.logger.error "QBO SSO state mismatch: expected #{session[:qbo_sso_state]}, got #{params[:state]}"
        redirect_to new_user_session_path, alert: 'Authentication failed. Please try again.'
        return
      end

      # Clear state from session after validation
      session.delete(:qbo_sso_state)

      # Exchange authorization code for tokens
      token_response = exchange_code_for_tokens(params[:code])

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
        redirect_to new_user_session_path, alert: 'Your QuickBooks email is not verified. Please verify your email with Intuit and try again.'
        return
      end

      # Find or create user (handles both new and returning users)
      user = QboSsoService.find_or_create_user(
        user_info: user_info,
        token_response: token_response,
        realm_id: params[:realmId]
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
