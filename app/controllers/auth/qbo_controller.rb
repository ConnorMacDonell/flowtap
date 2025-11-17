class Auth::QboController < ApplicationController
  before_action :authenticate_user!

  def connect
    # Generate and store state parameter for CSRF protection
    state = SecureRandom.hex(32)
    session[:qbo_oauth_state] = state

    redirect_to qbo_authorization_url(state), allow_other_host: true
  end

  # Handle OAuth callback from QuickBooks
  # Security: Implements 302 redirect pattern per Intuit requirements
  # Stores sensitive parameters in session and redirects to prevent token leakage via Referer header
  def callback
    # Store OAuth parameters in session (encrypted by Rails)
    session[:qbo_callback_params] = {
      code: params[:code],
      state: params[:state],
      realm_id: params[:realmId]
    }

    # Immediately issue 302 redirect to clean URL (no sensitive data in URL)
    # This prevents tokens from leaking via Referer header
    redirect_to auth_qbo_complete_path, status: :found  # 302 Found
  end

  # Complete the OAuth callback after 302 redirect
  # This action has a clean URL with no sensitive parameters
  def complete
    begin
      # Retrieve OAuth parameters from session
      callback_params = session.delete(:qbo_callback_params)

      unless callback_params
        Rails.logger.error "QBO: No callback params in session for user #{current_user.id}"
        redirect_to dashboard_path, alert: 'Authentication session expired. Please try again.'
        return
      end

      # Validate state parameter for CSRF protection
      unless callback_params[:state].present? && callback_params[:state] == session[:qbo_oauth_state]
        Rails.logger.error "QBO OAuth state mismatch: expected #{session[:qbo_oauth_state]}, got #{callback_params[:state]}"
        redirect_to dashboard_path, alert: 'OAuth state validation failed. Please try connecting again.'
        return
      end

      # Clear the state from session after validation
      session.delete(:qbo_oauth_state)

      token_response = exchange_code_for_tokens(callback_params[:code])

      # Validate ID token (OpenID Connect requirement)
      unless QboService.validate_id_token(qbo_client, token_response[:id_token])
        Rails.logger.error "QBO ID token validation failed for user #{current_user.id}"
        redirect_to dashboard_path, alert: 'Failed to validate QuickBooks identity. Please try again.'
        return
      end

      # Fetch user profile info from Intuit
      user_info = QboService.fetch_user_info(qbo_client, token_response[:access_token])

      unless user_info
        redirect_to dashboard_path, alert: 'Failed to retrieve user information from QuickBooks. Please try again.'
        return
      end

      # CRITICAL: Verify email is verified (per Intuit documentation requirement)
      unless user_info[:email_verified]
        Rails.logger.warn "QBO connection rejected - email not verified for user #{current_user.id}"
        redirect_to dashboard_path, alert: 'Your QuickBooks email is not verified. Please verify your email with Intuit and try again.'
        return
      end

      # Store all OAuth and OpenID data
      current_user.update!(
        qbo_realm_id: callback_params[:realm_id],
        qbo_access_token: token_response[:access_token],
        qbo_refresh_token: token_response[:refresh_token],
        qbo_token_expires_at: Time.current + token_response[:expires_in].seconds,
        qbo_connected_at: Time.current,
        qbo_id_token: token_response[:id_token],
        qbo_sub_id: user_info[:sub],
        qbo_user_email: user_info[:email],
        qbo_user_email_verified: user_info[:email_verified],
        qbo_user_given_name: user_info[:given_name],
        qbo_user_family_name: user_info[:family_name]
      )

      Rails.logger.info "QBO connected successfully for user #{current_user.id} (sub: #{user_info[:sub]})"
      redirect_to dashboard_path, notice: 'QuickBooks Online connected successfully!'
    rescue IntuitOAuth::OAuth2ClientException => e
      Rails.logger.error "QBO OAuth error: #{e.message}, intuit_tid: #{e.intuit_tid}"
      redirect_to dashboard_path, alert: 'Failed to connect to QuickBooks Online. Please try again.'
    rescue => e
      Rails.logger.error "QBO OAuth error: #{e.message}"
      redirect_to dashboard_path, alert: 'Failed to connect to QuickBooks Online. Please try again.'
    end
  end

  def disconnect
    # If user has a QBO connection, revoke tokens on Intuit's servers first
    if current_user.qbo_connected?
      begin
        qbo_service = QboService.new(current_user)

        unless qbo_service.revoke_tokens!
          redirect_to dashboard_path, alert: 'Failed to disconnect from QuickBooks. Please try again or contact support.'
          return
        end
      rescue ArgumentError
        # No valid connection - safe to disconnect locally
        Rails.logger.info("QBO disconnect: no valid connection for user #{current_user.id}, proceeding with local disconnect")
      rescue => e
        # Revocation failed - DO NOT disconnect locally
        Rails.logger.error("QBO disconnect: revoke failed for user #{current_user.id}: #{e.message}")
        redirect_to dashboard_path, alert: 'Failed to disconnect from QuickBooks. Please try again or contact support.'
        return
      end
    end

    # Only disconnect locally if revocation succeeded or there was no connection
    current_user.disconnect_qbo!
    redirect_to dashboard_path, notice: 'QuickBooks Online disconnected successfully.'
  end

  def status
    render json: {
      connected: current_user.qbo_connected?,
      valid: current_user.qbo_token_valid?,
      connected_at: current_user.qbo_connected_at,
      realm_id: current_user.qbo_realm_id
    }
  end

  def test_connection
    unless current_user.qbo_token_valid?
      return render json: {
        success: false,
        error: 'QBO not connected or token expired. Please reconnect.'
      }, status: :unauthorized
    end

    begin
      qbo_service = QboService.new(current_user)

      # Test basic connection
      connection_test = qbo_service.test_connection

      if connection_test
        # Get company info to verify access
        company_info = qbo_service.api.get(:companyinfo, 1)

        render json: {
          success: true,
          message: 'QBO connection successful!',
          company_name: company_info.dig('Name'),
          realm_id: current_user.qbo_realm_id,
          environment: ENV['QBO_ENVIRONMENT'] || 'sandbox'
        }
      else
        render json: {
          success: false,
          error: 'Failed to connect to QBO API'
        }, status: :service_unavailable
      end

    rescue => e
      Rails.logger.error "QBO test connection error: #{e.message}"
      render json: {
        success: false,
        error: "Connection failed: #{e.message}"
      }, status: :service_unavailable
    end
  end

  private

  def qbo_client
    @qbo_client ||= IntuitOAuth::Client.new(
      ENV['QBO_CLIENT_ID'],
      ENV['QBO_CLIENT_SECRET'],
      auth_qbo_callback_url,
      ENV['QBO_ENVIRONMENT'] || 'sandbox'
    )
  end

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

    # SDK generates its own state parameter, but we need to use our own for session tracking
    # Replace the SDK's state parameter with our own
    uri = URI.parse(auth_url)
    params = Rack::Utils.parse_query(uri.query)
    params['state'] = state
    uri.query = params.to_query

    uri.to_s
  end

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