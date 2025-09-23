class FreelancerService
  attr_reader :user, :base_url

  def initialize(user)
    @user = user
    @token_refresh_attempted = false

    # Allow initialization if user can refresh token, not just if currently valid
    unless @user.freelancer_connected? || @user.freelancer_can_refresh?
      raise ArgumentError, 'User must have valid Freelancer connection or ability to refresh'
    end

    @base_url = freelancer_environment == 'production' ?
      'https://www.freelancer.com' :
      'https://www.freelancer-sandbox.com'
  end

  def get_user_info
    make_request('GET', '/api/users/0.1/self/')
  end

  def get_projects(limit: 10)
    make_request('GET', "/api/projects/0.1/projects/?limit=#{limit}")
  end

  def get_bids(limit: 10)
    make_request('GET', "/api/projects/0.1/bids/?bidders[]=#{@user.freelancer_user_id}&limit=#{limit}")
  end

  def test_connection
    user_info = get_user_info
    !!(user_info && user_info.dig('result', 'id').present?)
  rescue
    false
  end

  def refresh_token!
    return false unless @user.freelancer_can_refresh?

    Rails.logger.info "Freelancer API: Attempting to refresh token for user #{@user.id}"

    connection = Faraday.new(url: token_endpoint_url) do |conn|
      conn.request :url_encoded
      conn.response :json
    end

    response = connection.post do |req|
      req.body = {
        'grant_type' => 'refresh_token',
        'refresh_token' => @user.freelancer_refresh_token,
        'client_id' => freelancer_client_id,
        'client_secret' => freelancer_client_secret
      }
    end

    if response.success?
      token_data = response.body

      # Validate required fields are present
      unless token_data['access_token'].present?
        Rails.logger.error "Freelancer token refresh failed: No access_token in response"
        return false
      end

      @user.update!(
        freelancer_access_token: token_data['access_token'],
        freelancer_refresh_token: token_data['refresh_token'] || @user.freelancer_refresh_token,
        freelancer_token_expires_at: Time.current + (token_data['expires_in'] || 2592000).seconds,
        freelancer_scopes: token_data['scope'] || @user.freelancer_scopes
      )

      Rails.logger.info "Freelancer API: Successfully refreshed token for user #{@user.id}"
      @token_refresh_attempted = false # Reset for future requests
      true
    else
      Rails.logger.error "Freelancer token refresh failed: #{response.status} - #{response.body}"

      # If refresh token is invalid, we might need to clear it
      if response.status == 400 && response.body.to_s.include?('invalid_grant')
        Rails.logger.warn "Freelancer refresh token appears invalid for user #{@user.id}"
      end

      false
    end
  rescue => e
    Rails.logger.error "Freelancer token refresh error: #{e.message}"
    false
  end

  private

  def make_request(method, path, params = {})
    # Ensure we have a valid token before making request
    ensure_valid_token!

    connection = Faraday.new(url: @base_url) do |conn|
      conn.response :json
      conn.request :json if method.upcase == 'POST'
    end

    response = connection.send(method.downcase) do |req|
      req.url path
      req.headers['Freelancer-OAuth-V1'] = @user.freelancer_access_token
      req.body = params if method.upcase == 'POST' && params.any?
    end

    if response.success?
      response.body
    else
      Rails.logger.error "Freelancer API error: #{response.status} - #{response.body}"

      # If unauthorized and we haven't tried refreshing yet, try once
      if response.status == 401 && !@token_refresh_attempted && @user.freelancer_can_refresh?
        Rails.logger.info "Freelancer API: Attempting token refresh due to 401 response"
        @token_refresh_attempted = true

        if refresh_token!
          # Reset auth header with new token and retry
          return make_request(method, path, params)
        else
          Rails.logger.error "Freelancer API: Token refresh failed, cannot retry request"
        end
      end

      nil
    end
  rescue => e
    Rails.logger.error "Freelancer API request error: #{e.message}"
    nil
  end

  def ensure_valid_token!
    # If token is expired or expiring soon, try to refresh
    if @user.freelancer_needs_refresh? && @user.freelancer_can_refresh? && !@token_refresh_attempted
      Rails.logger.info "Freelancer API: Proactively refreshing token before request"
      refresh_token!
    elsif @user.freelancer_token_expired? && !@user.freelancer_can_refresh?
      raise ArgumentError, 'Freelancer token expired and cannot be refreshed. User needs to reauthorize.'
    elsif !@user.freelancer_token_valid? && !@user.freelancer_can_refresh?
      raise ArgumentError, 'No valid Freelancer token available and cannot refresh. User needs to authorize.'
    end
  end

  def token_endpoint_url
    base_auth_url = freelancer_environment == 'production' ?
      'https://accounts.freelancer.com' :
      'https://accounts.freelancer-sandbox.com'
    "#{base_auth_url}/oauth/token"
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
end