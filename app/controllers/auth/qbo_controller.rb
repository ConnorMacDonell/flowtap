class Auth::QboController < ApplicationController
  before_action :authenticate_user!

  def connect
    # Generate and store state parameter for CSRF protection
    state = SecureRandom.hex(32)
    session[:qbo_oauth_state] = state

    redirect_to qbo_authorization_url(state), allow_other_host: true
  end

  def callback
    begin
      # Validate state parameter for CSRF protection
      unless params[:state].present? && params[:state] == session[:qbo_oauth_state]
        Rails.logger.error "QBO OAuth state mismatch: expected #{session[:qbo_oauth_state]}, got #{params[:state]}"
        redirect_to dashboard_path, alert: 'OAuth state validation failed. Please try connecting again.'
        return
      end

      # Clear the state from session after validation
      session.delete(:qbo_oauth_state)

      token_response = exchange_code_for_tokens(params[:code])
      
      current_user.update!(
        qbo_realm_id: params[:realmId],
        qbo_access_token: token_response['access_token'],
        qbo_refresh_token: token_response['refresh_token'],
        qbo_token_expires_at: Time.current + token_response['expires_in'].seconds,
        qbo_connected_at: Time.current
      )

      redirect_to dashboard_path, notice: 'QuickBooks Online connected successfully!'
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

  def qbo_authorization_url(state)
    # QBO OAuth2 uses the same authorization endpoint for both sandbox and production
    # The environment is determined by the app keys, not the URL
    base_url = 'https://appcenter.intuit.com'
    params = {
      'client_id' => ENV['QBO_CLIENT_ID'],
      'scope' => 'com.intuit.quickbooks.accounting',
      'redirect_uri' => auth_qbo_callback_url,
      'response_type' => 'code',
      'access_type' => 'offline',
      'state' => state
    }
    "#{base_url}/connect/oauth2?#{params.to_query}"
  end

  def exchange_code_for_tokens(code)
    connection = Faraday.new(url: token_endpoint_url) do |conn|
      conn.request :url_encoded
      conn.response :json
    end

    response = connection.post do |req|
      req.headers['Authorization'] = "Basic #{Base64.strict_encode64("#{ENV['QBO_CLIENT_ID']}:#{ENV['QBO_CLIENT_SECRET']}")}"
      req.body = {
        'grant_type' => 'authorization_code',
        'code' => code,
        'redirect_uri' => auth_qbo_callback_url
      }
    end

    unless response.success?
      raise "Token exchange failed: #{response.body}"
    end

    response.body
  end

  def token_endpoint_url
    # QBO uses the same token endpoint for both sandbox and production
    'https://oauth.platform.intuit.com/oauth2/v1/tokens/bearer'
  end
end