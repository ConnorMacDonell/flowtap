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

  # OpenID Connect class methods for authentication flow
  def self.validate_id_token(oauth_client, id_token)
    return false unless id_token.present?

    begin
      oauth_client.openid.validate_id_token(id_token)
    rescue IntuitOAuth::OAuth2ClientException => e
      Rails.logger.error("QBO ID token validation failed: #{e.message}")
      false
    rescue => e
      Rails.logger.error("QBO ID token validation error: #{e.message}")
      false
    end
  end

  def self.fetch_user_info(oauth_client, access_token)
    return nil unless access_token.present?

    begin
      response = oauth_client.openid.get_user_info(access_token)

      {
        sub: response['sub'],
        email: response['email'],
        email_verified: response['emailVerified'],
        given_name: response['givenName'],
        family_name: response['familyName']
      }
    rescue IntuitOAuth::OAuth2ClientException => e
      Rails.logger.error("QBO user info fetch failed: #{e.message}, intuit_tid: #{e.intuit_tid}")
      nil
    rescue => e
      Rails.logger.error("QBO user info fetch error: #{e.message}")
      nil
    end
  end

  def initialize(user)
    @user = user
    @token_refresh_attempted = false

    # Allow initialization if user has valid token or can refresh expired token
    unless @user.qbo_token_valid? || @user.qbo_can_refresh?
      raise ArgumentError, 'User must have valid QBO connection or ability to refresh. Please reauthorize.'
    end

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
    # Ensure we have a valid token before making request
    ensure_valid_token!

    response = @qbo_api.get(:companyinfo, 1)
    response.present?
  rescue QboApi::Unauthorized => e
    # Try to refresh token and retry once on 401
    if !@token_refresh_attempted && @user.qbo_can_refresh?
      Rails.logger.info "QBO API: Attempting token refresh due to 401 response for user #{@user.id}"
      @token_refresh_attempted = true

      if refresh_token!
        @user.reload
        # Retry the API call with new token, catching any errors
        begin
          response = @qbo_api.get(:companyinfo, 1)
          return response.present?
        rescue QboApi::Unauthorized, QboApi::Error => retry_error
          # Second 401 or other error after refresh - log and return false
          log_qbo_error('test_connection', retry_error)
          return false
        end
      else
        Rails.logger.error "QBO API: Token refresh failed, cannot retry request"
      end
    end

    log_qbo_error('test_connection', e)
    false
  rescue QboApi::Error => e
    log_qbo_error('test_connection', e)
    false
  rescue => e
    log_error('test_connection', e)
    false
  end

  def refresh_token!
    return false unless @user.qbo_refresh_token.present?

    token_response = qbo_oauth_client.token.refresh_tokens(@user.qbo_refresh_token)

    @user.update!(
      qbo_access_token: token_response.access_token,
      qbo_refresh_token: token_response.refresh_token,
      qbo_token_expires_at: Time.current + token_response.expires_in.seconds
    )

    # Update the API client with new access token
    @qbo_api = QboApi.new(
      access_token: @user.qbo_access_token,
      realm_id: @user.qbo_realm_id
    )

    Rails.logger.info("QBO token refreshed successfully for user #{@user.id}")
    @token_refresh_attempted = false # Reset for future requests
    true
  rescue IntuitOAuth::OAuth2ClientException => e
    handle_oauth_error(e)
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

    qbo_oauth_client.token.revoke_tokens(token_to_revoke)
    Rails.logger.info("QBO tokens revoked successfully for user #{@user.id} (realm: #{@user.qbo_realm_id})")
    true
  rescue IntuitOAuth::OAuth2ClientException => e
    handle_oauth_error(e)
    false
  rescue => e
    log_error('revoke_tokens', e)
    false
  end

  private

  def ensure_valid_token!
    # If token is expired or expiring soon, try to refresh proactively
    if @user.qbo_needs_refresh? && @user.qbo_can_refresh? && !@token_refresh_attempted
      Rails.logger.info "QBO API: Proactively refreshing token before request for user #{@user.id}"
      if refresh_token!
        @user.reload
      end
    elsif @user.qbo_token_expired? && !@user.qbo_can_refresh?
      raise ArgumentError, 'QBO token expired and cannot be refreshed. User needs to reauthorize.'
    elsif !@user.qbo_token_valid? && !@user.qbo_can_refresh?
      raise ArgumentError, 'No valid QBO token available and cannot refresh. User needs to authorize.'
    end
  end

  def qbo_oauth_client
    @qbo_oauth_client ||= IntuitOAuth::Client.new(
      ENV['QBO_CLIENT_ID'],
      ENV['QBO_CLIENT_SECRET'],
      '', # redirect_uri not needed for token refresh/revoke
      ENV['QBO_ENVIRONMENT'] || 'sandbox'
    )
  end

  def handle_oauth_error(error)
    log_data = {
      user_id: @user.id,
      error_class: error.class.name,
      error_message: error.message,
      status_code: error.status_code,
      intuit_tid: error.intuit_tid,
      timestamp: Time.current
    }

    # Handle specific error cases based on message content
    if error.message.include?('invalid_grant')
      Rails.logger.error("QBO invalid_grant error - refresh token expired or revoked: #{log_data.to_json}")
      # User needs to reconnect their QBO account
      @user.update(qbo_refresh_token: nil) # Clear invalid refresh token
    else
      Rails.logger.error("QBO OAuth error: #{log_data.to_json}")
    end

    # Create audit log entry for security/compliance
    AuditLog.create(
      user_id: @user.id,
      action: 'qbo_oauth_error',
      metadata: log_data
    ) rescue nil
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