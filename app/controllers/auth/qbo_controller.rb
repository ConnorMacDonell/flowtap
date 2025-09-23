class Auth::QboController < ApplicationController
  before_action :authenticate_user!

  def connect
    redirect_to qbo_authorization_url, allow_other_host: true
  end

  def callback
    begin
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

  def qbo_authorization_url
    base_url = Rails.env.production? ? 'https://appcenter.intuit.com' : 'https://appcenter-sandbox.intuit.com'
    params = {
      'client_id' => ENV['QBO_CLIENT_ID'],
      'scope' => 'com.intuit.quickbooks.accounting',
      'redirect_uri' => auth_qbo_callback_url,
      'response_type' => 'code',
      'access_type' => 'offline'
    }
    "#{base_url}/connect/oauth2?#{params.to_query}"
  end

  def exchange_code_for_tokens(code)
    connection = Faraday.new(url: token_endpoint_url) do |conn|
      conn.request :url_encoded
      conn.response :json
      conn.basic_auth(ENV['QBO_CLIENT_ID'], ENV['QBO_CLIENT_SECRET'])
    end

    response = connection.post do |req|
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
    Rails.env.production? ? 'https://oauth.platform.intuit.com/oauth2/v1/tokens/bearer' : 'https://oauth.platform.intuit.com/oauth2/v1/tokens/bearer'
  end
end