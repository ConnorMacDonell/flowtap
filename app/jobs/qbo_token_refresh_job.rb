class QboTokenRefreshJob < ApplicationJob
  queue_as :default

  # Retry failed token refreshes with exponential backoff
  retry_on StandardError, wait: :exponentially_longer, attempts: 3

  # Don't retry if the user record is deleted
  discard_on ActiveJob::DeserializationError

  def perform(user_id = nil)
    if user_id
      # Refresh token for specific user
      refresh_user_token(user_id)
    else
      # Refresh tokens for all users who need it
      refresh_all_expiring_tokens
    end
  end

  private

  def refresh_all_expiring_tokens
    # Find users whose tokens expire soon or are already expired but can be refreshed
    users_needing_refresh = User.where.not(qbo_refresh_token: nil)
                               .where('qbo_token_expires_at <= ? OR qbo_token_expires_at IS NULL', 7.days.from_now)
                               .where('qbo_connected_at > ?', 180.days.ago) # QBO refresh tokens expire after ~180 days

    Rails.logger.info "QboTokenRefreshJob: Found #{users_needing_refresh.count} users needing token refresh"

    users_needing_refresh.find_each do |user|
      refresh_user_token(user.id)
    rescue => e
      Rails.logger.error "QboTokenRefreshJob: Failed to refresh token for user #{user.id}: #{e.message}"
      # Continue processing other users even if one fails
    end
  end

  def refresh_user_token(user_id)
    user = User.find(user_id)

    unless user.qbo_can_refresh?
      Rails.logger.warn "QboTokenRefreshJob: User #{user_id} cannot refresh token (refresh token expired or missing)"
      notify_user_of_reauth_needed(user)
      return
    end

    service = QboService.new(user)

    if service.refresh_token!
      Rails.logger.info "QboTokenRefreshJob: Successfully refreshed token for user #{user_id}"
    else
      Rails.logger.error "QboTokenRefreshJob: Failed to refresh token for user #{user_id}"
      notify_user_of_reauth_needed(user)
    end
  rescue ArgumentError => e
    # User doesn't have valid connection - skip
    Rails.logger.debug "QboTokenRefreshJob: Skipping user #{user_id}: #{e.message}"
  rescue => e
    Rails.logger.error "QboTokenRefreshJob: Error refreshing token for user #{user_id}: #{e.message}"
    raise # Re-raise to trigger retry mechanism
  end

  def notify_user_of_reauth_needed(user)
    # TODO: Implement user notification when manual reauthorization is needed
    # This could be an email notification or in-app notification
    Rails.logger.info "QboTokenRefreshJob: User #{user.id} needs manual reauthorization"
  end
end