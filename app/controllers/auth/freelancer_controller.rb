class Auth::FreelancerController < ApplicationController
  before_action :authenticate_user!

  def connect
    redirect_to freelancer_authorization_url, allow_other_host: true
  end

  def callback
    begin
      # Verify state parameter for security
      if params[:state] != session[:freelancer_oauth_state]
        raise 'Invalid state parameter'
      end

      token_response = exchange_code_for_tokens(params[:code])

      current_user.update!(
        freelancer_user_id: extract_user_id_from_token(token_response['access_token']),
        freelancer_access_token: token_response['access_token'],
        freelancer_refresh_token: token_response['refresh_token'],
        freelancer_token_expires_at: Time.current + token_response['expires_in'].seconds,
        freelancer_scopes: token_response['scope'],
        freelancer_connected_at: Time.current
      )

      # Clear the state from session
      session.delete(:freelancer_oauth_state)

      redirect_to dashboard_path, notice: 'Freelancer account connected successfully!'
    rescue => e
      Rails.logger.error "Freelancer OAuth error: #{e.message}"
      session.delete(:freelancer_oauth_state)
      redirect_to dashboard_path, alert: 'Failed to connect to Freelancer. Please try again.'
    end
  end

  def disconnect
    current_user.disconnect_freelancer!
    redirect_to dashboard_path, notice: 'Freelancer account disconnected successfully.'
  end

  def status
    render json: {
      connected: current_user.freelancer_connected?,
      valid: current_user.freelancer_token_valid?,
      connected_at: current_user.freelancer_connected_at,
      user_id: current_user.freelancer_user_id,
      scopes: current_user.freelancer_scopes
    }
  end

  def test_connection
    # Check if user has any Freelancer connection at all
    unless current_user.freelancer_connected?
      return render json: {
        success: false,
        error: 'Freelancer not connected. Please connect your account first.'
      }, status: :unauthorized
    end

    # If token is expired but we can refresh, try automatic refresh
    if current_user.freelancer_token_expired? && current_user.freelancer_can_refresh?
      Rails.logger.info "FreelancerController: Attempting automatic token refresh for user #{current_user.id}"
    end

    begin
      freelancer_service = FreelancerService.new(current_user)

      # Test basic connection by getting user info (this will auto-refresh if needed)
      user_info = freelancer_service.get_user_info

      if user_info && user_info.dig('result', 'id').present?
        render json: {
          success: true,
          message: 'Freelancer connection successful!',
          user_info: {
            id: user_info.dig('result', 'id'),
            username: user_info.dig('result', 'username'),
            display_name: user_info.dig('result', 'display_name')
          },
          environment: freelancer_environment,
          token_expires_at: current_user.freelancer_token_expires_at
        }
      else
        render json: {
          success: false,
          error: 'Failed to connect to Freelancer API'
        }, status: :service_unavailable
      end

    rescue ArgumentError => e
      # Handle cases where token cannot be refreshed
      if e.message.include?('reauthorize') || e.message.include?('authorize')
        render json: {
          success: false,
          error: 'Your Freelancer authorization has expired. Please reconnect your account.',
          requires_reauth: true
        }, status: :unauthorized
      else
        Rails.logger.error "Freelancer test connection argument error: #{e.message}"
        render json: {
          success: false,
          error: "Connection failed: #{e.message}"
        }, status: :service_unavailable
      end
    rescue => e
      Rails.logger.error "Freelancer test connection error: #{e.message}"
      render json: {
        success: false,
        error: "Connection failed: #{e.message}"
      }, status: :service_unavailable
    end
  end

  private

  def freelancer_authorization_url
    # Generate a secure state parameter
    state = SecureRandom.hex(32)
    session[:freelancer_oauth_state] = state

    base_url = freelancer_environment == 'production' ?
      'https://accounts.freelancer.com' :
      'https://accounts.freelancer-sandbox.com'

    params = {
      'response_type' => 'code',
      'client_id' => freelancer_client_id,
      'redirect_uri' => freelancer_redirect_uri,
      'scope' => 'basic fln:project_manage',
      'prompt' => 'consent',
      'state' => state
    }

    "#{base_url}/oauth/authorize?#{params.to_query}"
  end

  def exchange_code_for_tokens(code)
    connection = Faraday.new(url: token_endpoint_url) do |conn|
      conn.request :url_encoded
      conn.response :json
    end

    response = connection.post do |req|
      req.body = {
        'grant_type' => 'authorization_code',
        'code' => code,
        'client_id' => freelancer_client_id,
        'client_secret' => freelancer_client_secret,
        'redirect_uri' => freelancer_redirect_uri
      }
    end

    unless response.success?
      raise "Token exchange failed: #{response.body}"
    end

    response.body
  end

  def extract_user_id_from_token(access_token)
    # Make a quick API call to get user info and extract user ID
    connection = Faraday.new(url: api_base_url) do |conn|
      conn.response :json
    end

    response = connection.get('/api/users/0.1/self/') do |req|
      req.headers['Freelancer-OAuth-V1'] = access_token
    end

    if response.success?
      response.body.dig('result', 'id')
    else
      nil # Will be handled by the calling method
    end
  end

  def token_endpoint_url
    base_url = freelancer_environment == 'production' ?
      'https://accounts.freelancer.com' :
      'https://accounts.freelancer-sandbox.com'
    "#{base_url}/oauth/token"
  end

  def api_base_url
    freelancer_environment == 'production' ?
      'https://www.freelancer.com' :
      'https://www.freelancer-sandbox.com'
  end

  def freelancer_environment
    ENV['FREELANCER_ENVIRONMENT'] || 'sandbox'
  end

  def freelancer_client_id
    if freelancer_environment == 'production'
      ENV['FREELANCER_CLIENT_ID']
    else
      ENV['FREELANCER_SANDBOX_CLIENT_ID'] || ENV['FREELANCER_CLIENT_ID']
    end
  end

  def freelancer_client_secret
    if freelancer_environment == 'production'
      ENV['FREELANCER_CLIENT_SECRET']
    else
      ENV['FREELANCER_SANDBOX_CLIENT_SECRET'] || ENV['FREELANCER_CLIENT_SECRET']
    end
  end

  def freelancer_redirect_uri
    if Rails.env.development?
      'http://localhost:3000/auth/freelancer/callback'
    else
      auth_freelancer_callback_url
    end
  end
end