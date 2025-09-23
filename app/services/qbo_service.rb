class QboService
  def initialize(user)
    @user = user
    raise ArgumentError, 'User must have valid QBO connection' unless @user.qbo_token_valid?
    
    @qbo_api = QboApi.new(
      access_token: @user.qbo_access_token,
      realm_id: @user.qbo_realm_id
    )
    
    # Configure for production or sandbox
    QboApi.production = (ENV['QBO_ENVIRONMENT'] == 'production')
  end

  def api
    @qbo_api
  end

  def test_connection
    @qbo_api.get(:companyinfo, 1).present?
  rescue
    false
  end

  def refresh_token!
    return false unless @user.qbo_refresh_token.present?

    connection = Faraday.new(url: 'https://oauth.platform.intuit.com/oauth2/v1/tokens/bearer') do |conn|
      conn.request :url_encoded
      conn.response :json
    end

    response = connection.post do |req|
      req.headers['Authorization'] = "Basic #{Base64.strict_encode64("#{ENV['QBO_CLIENT_ID']}:#{ENV['QBO_CLIENT_SECRET']}")}"
      req.body = {
        'grant_type' => 'refresh_token',
        'refresh_token' => @user.qbo_refresh_token
      }
    end

    if response.success?
      token_data = response.body
      @user.update!(
        qbo_access_token: token_data['access_token'],
        qbo_refresh_token: token_data['refresh_token'] || @user.qbo_refresh_token,
        qbo_token_expires_at: Time.current + token_data['expires_in'].seconds
      )
      
      # Update the API client with new token
      @qbo_api = QboApi.new(
        access_token: @user.qbo_access_token,
        realm_id: @user.qbo_realm_id
      )
      
      true
    else
      false
    end
  rescue
    false
  end
end