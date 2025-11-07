class FreelancerTokenRefreshJob < ApplicationJob
  queue_as :default

  # Retry failed token refreshes with polynomial backoff
  retry_on StandardError, wait: :polynomially_longer, attempts: 3

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
    users_needing_refresh = User.where.not(freelancer_refresh_token: nil)
                               .where('freelancer_token_expires_at <= ? OR freelancer_token_expires_at IS NULL', 7.days.from_now)
                               .where('freelancer_connected_at > ?', 6.months.ago) # Ensure refresh token hasn't expired

    Rails.logger.info "FreelancerTokenRefreshJob: Found #{users_needing_refresh.count} users needing token refresh"

    users_needing_refresh.find_each do |user|
      refresh_user_token(user.id)
    rescue => e
      Rails.logger.error "FreelancerTokenRefreshJob: Failed to refresh token for user #{user.id}: #{e.message}"
      # Continue processing other users even if one fails
    end
  end

  def refresh_user_token(user_id)
    user = User.find(user_id)

    unless user.freelancer_can_refresh?
      Rails.logger.warn "FreelancerTokenRefreshJob: User #{user_id} cannot refresh token (refresh token expired or missing)"
      notify_user_of_reauth_needed(user)
      return
    end

    service = FreelancerService.new(user)

    if service.refresh_token!
      Rails.logger.info "FreelancerTokenRefreshJob: Successfully refreshed token for user #{user_id}"
    else
      Rails.logger.error "FreelancerTokenRefreshJob: Failed to refresh token for user #{user_id}"
      notify_user_of_reauth_needed(user)
    end
  rescue ArgumentError => e
    # User doesn't have valid connection - skip
    Rails.logger.debug "FreelancerTokenRefreshJob: Skipping user #{user_id}: #{e.message}"
  rescue => e
    Rails.logger.error "FreelancerTokenRefreshJob: Error refreshing token for user #{user_id}: #{e.message}"
    raise # Re-raise to trigger retry mechanism
  end

  def notify_user_of_reauth_needed(user)
    # TODO: Implement user notification when manual reauthorization is needed
    # This could be an email notification or in-app notification
    Rails.logger.info "FreelancerTokenRefreshJob: User #{user.id} needs manual reauthorization"
  end
end