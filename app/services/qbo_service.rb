class QboService
  class QboApiError < StandardError
    attr_reader :error_code, :error_detail, :intuit_tid

    def initialize(message, error_code: nil, error_detail: nil, intuit_tid: nil)
      super(message)
      @error_code = error_code
      @error_detail = error_detail
      @intuit_tid = intuit_tid
    end
  end

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
    response = @qbo_api.get(:companyinfo, 1)
    response.present?
  rescue QboApi::Error => e
    log_qbo_error('test_connection', e)
    false
  rescue => e
    log_error('test_connection', e)
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

      # Update the API client with new refresh token
      @qbo_api = QboApi.new(
        access_token: @user.qbo_access_token,
        realm_id: @user.qbo_realm_id
      )

      Rails.logger.info("QBO token refreshed successfully for user #{@user.id}")
      true
    else
      handle_token_refresh_error(response)
      false
    end
  rescue Faraday::Error => e
    log_error('refresh_token', e)
    false
  rescue => e
    log_error('refresh_token', e)
    false
  end

  def revoke_tokens!
    # Prefer refresh token (invalidates both tokens), fallback to access token
    token_to_revoke = @user.qbo_refresh_token.presence || @user.qbo_access_token.presence

    unless token_to_revoke
      Rails.logger.warn("QBO revoke: no tokens to revoke for user #{@user.id}")
      return false
    end

    connection = Faraday.new(url: 'https://developer.api.intuit.com') do |conn|
      conn.request :url_encoded
      conn.response :json
    end

    response = connection.post('/v2/oauth2/tokens/revoke') do |req|
      req.headers['Authorization'] = "Basic #{Base64.strict_encode64("#{ENV['QBO_CLIENT_ID']}:#{ENV['QBO_CLIENT_SECRET']}")}"
      req.headers['Content-Type'] = 'application/json'
      req.body = {
        'token' => token_to_revoke
      }.to_json
    end

    if response.success?
      Rails.logger.info("QBO tokens revoked successfully for user #{@user.id} (realm: #{@user.qbo_realm_id})")
      true
    else
      log_data = {
        user_id: @user.id,
        realm_id: @user.qbo_realm_id,
        status: response.status,
        error_body: response.body,
        timestamp: Time.current
      }
      Rails.logger.error("QBO token revocation failed: #{log_data.to_json}")
      false
    end
  rescue Faraday::Error => e
    log_error('revoke_tokens', e)
    false
  rescue => e
    log_error('revoke_tokens', e)
    false
  end

  private

  def handle_token_refresh_error(response)
    error_body = response.body
    error_code = error_body['error'] if error_body.is_a?(Hash)

    # Log detailed error information
    log_data = {
      user_id: @user.id,
      error_code: error_code,
      error_description: error_body.is_a?(Hash) ? error_body['error_description'] : error_body,
      status: response.status,
      timestamp: Time.current
    }

    # Handle specific error cases
    case error_code
    when 'invalid_grant'
      Rails.logger.error("QBO invalid_grant error - refresh token expired or revoked: #{log_data.to_json}")
      # User needs to reconnect their QBO account
      @user.update(qbo_refresh_token: nil) # Clear invalid refresh token
    else
      Rails.logger.error("QBO token refresh failed: #{log_data.to_json}")
    end
  end

  def log_qbo_error(method_name, error)
    intuit_tid = extract_intuit_tid(error)

    log_data = {
      service: 'QboService',
      method: method_name,
      user_id: @user.id,
      error_class: error.class.name,
      error_message: error.message,
      intuit_tid: intuit_tid,
      timestamp: Time.current
    }

    Rails.logger.error("QBO API error: #{log_data.to_json}")

    # Create audit log entry for security/compliance
    AuditLog.create(
      user_id: @user.id,
      action: 'qbo_api_error',
      metadata: log_data.merge(intuit_tid: intuit_tid)
    ) rescue nil
  end

  def log_error(method_name, error)
    log_data = {
      service: 'QboService',
      method: method_name,
      user_id: @user.id,
      error_class: error.class.name,
      error_message: error.message,
      backtrace: error.backtrace&.first(5),
      timestamp: Time.current
    }

    Rails.logger.error("QBO Service error: #{log_data.to_json}")
  end

  def extract_intuit_tid(error)
    # Try to extract intuit_tid from error response if available
    return nil unless error.respond_to?(:response)

    response = error.response
    if response.is_a?(Hash) && response['Fault']
      response['Fault']['intuit_tid']
    elsif response.respond_to?(:headers)
      response.headers['intuit_tid']
    end
  rescue
    nil
  end
end