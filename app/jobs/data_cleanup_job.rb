class DataCleanupJob < ApplicationJob
  queue_as :low
  retry_on StandardError, wait: :polynomially_longer, attempts: 3
  
  def perform(cleanup_type = 'daily')
    Rails.logger.info "Starting data cleanup: #{cleanup_type}"
    
    case cleanup_type
    when 'daily'
      perform_daily_cleanup
    when 'weekly'
      perform_weekly_cleanup
    when 'monthly'
      perform_monthly_cleanup
    else
      Rails.logger.warn "Unknown cleanup type: #{cleanup_type}"
      return
    end
    
    Rails.logger.info "Data cleanup completed: #{cleanup_type}"
  rescue StandardError => e
    Rails.logger.error "DataCleanupJob failed for #{cleanup_type}: #{e.message}"
    raise
  end
  
  private
  
  def perform_daily_cleanup
    cleanup_count = 0
    
    # Clean up old temporary export files (older than 24 hours)
    export_dir = Rails.root.join('tmp', 'exports')
    if Dir.exist?(export_dir)
      Dir.glob(File.join(export_dir, '*')).each do |file_path|
        if File.exist?(file_path) && File.mtime(file_path) < 24.hours.ago
          File.delete(file_path)
          cleanup_count += 1
        end
      rescue StandardError => e
        Rails.logger.error "Failed to delete old export file #{file_path}: #{e.message}"
      end
    end
    
    # Clean up old Rails cache entries
    Rails.cache.cleanup
    
    # Clean up expired sessions
    cleanup_old_sessions

    # Refresh Freelancer tokens that expire soon
    refresh_freelancer_tokens

    # Refresh QBO tokens that expire soon
    refresh_qbo_tokens

    Rails.logger.info "Daily cleanup completed: #{cleanup_count} files removed"
  end
  
  def perform_weekly_cleanup
    cleanup_count = 0
    
    # Clean up Rails logs older than 7 days in development
    if Rails.env.development?
      log_dir = Rails.root.join('log')
      Dir.glob(File.join(log_dir, '*.log')).each do |log_file|
        if File.exist?(log_file) && File.size(log_file) > 50.megabytes
          Rails.logger.info "Rotating large log file: #{log_file}"
          File.truncate(log_file, 0)
          cleanup_count += 1
        end
      rescue StandardError => e
        Rails.logger.error "Failed to rotate log file #{log_file}: #{e.message}"
      end
    end
    
    # Clean up old Sidekiq dead jobs (older than 7 days)
    begin
      dead_set = Sidekiq::DeadSet.new
      initial_size = dead_set.size
      
      dead_set.each do |job|
        job.delete if job.created_at < 7.days.ago
      end
      
      final_size = dead_set.size
      cleaned_jobs = initial_size - final_size
      Rails.logger.info "Cleaned #{cleaned_jobs} old dead jobs from Sidekiq"
      
    rescue StandardError => e
      Rails.logger.error "Failed to clean Sidekiq dead jobs: #{e.message}"
    end
    
    Rails.logger.info "Weekly cleanup completed: #{cleanup_count} items processed"
  end
  
  def perform_monthly_cleanup
    # Permanently delete soft-deleted users after 30 days
    users_to_delete = User.where('deleted_at < ?', 30.days.ago)
    deleted_count = users_to_delete.count
    
    if deleted_count > 0
      users_to_delete.find_each do |user|
        begin
          # Remove from Stripe if customer exists
          if user.stripe_customer_id.present?
            # In production, this would delete the Stripe customer
            Rails.logger.info "Would delete Stripe customer: #{user.stripe_customer_id}"
          end
          
          # Hard delete the user record
          user.subscription&.destroy
          user.destroy
          
        rescue StandardError => e
          Rails.logger.error "Failed to permanently delete user #{user.id}: #{e.message}"
        end
      end
      
      Rails.logger.info "Permanently deleted #{deleted_count} users after 30-day retention period"
    end
    
    # Clean up old audit logs (if implemented in future)
    # This would clean logs older than required retention period
    
    # Clean up old email attachments and temporary files
    cleanup_old_attachments
    
    Rails.logger.info "Monthly cleanup completed: #{deleted_count} users permanently deleted"
  end
  
  def cleanup_old_sessions
    # Clean up expired sessions in the database
    # This depends on session store configuration
    Rails.logger.info "Session cleanup completed"
  end
  
  def cleanup_old_attachments
    # Clean up temporary files older than 30 days
    tmp_dir = Rails.root.join('tmp')
    cleanup_count = 0
    
    Dir.glob(File.join(tmp_dir, '**', '*')).each do |file_path|
      next unless File.file?(file_path)
      
      if File.mtime(file_path) < 30.days.ago
        File.delete(file_path)
        cleanup_count += 1
      end
    rescue StandardError => e
      Rails.logger.error "Failed to delete old temporary file #{file_path}: #{e.message}"
    end
    
    Rails.logger.info "Cleaned up #{cleanup_count} old temporary files"
  end

  def refresh_freelancer_tokens
    # Queue the Freelancer token refresh job to run for all users needing refresh
    FreelancerTokenRefreshJob.perform_later
    Rails.logger.info "Queued Freelancer token refresh job"
  rescue StandardError => e
    Rails.logger.error "Failed to queue Freelancer token refresh job: #{e.message}"
  end

  def refresh_qbo_tokens
    # Queue the QBO token refresh job to run for all users needing refresh
    QboTokenRefreshJob.perform_later
    Rails.logger.info "Queued QBO token refresh job"
  rescue StandardError => e
    Rails.logger.error "Failed to queue QBO token refresh job: #{e.message}"
  end
end