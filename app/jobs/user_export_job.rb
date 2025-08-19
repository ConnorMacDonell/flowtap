class UserExportJob < ApplicationJob
  queue_as :low
  retry_on StandardError, wait: :polynomially_longer, attempts: 3
  
  def perform(user_id, admin_user_id = nil)
    Rails.logger.info "Starting user export for user_id: #{user_id}"
    
    user = User.find(user_id)
    admin_user = AdminUser.find(admin_user_id) if admin_user_id
    
    # Generate user data export
    export_data = generate_user_export(user)
    
    # Create temporary file with better naming
    timestamp = Time.current.strftime('%Y%m%d_%H%M%S')
    filename = "user_export_#{user.id}_#{timestamp}.json"
    file_path = Rails.root.join('tmp', 'exports', filename)
    
    # Ensure exports directory exists
    FileUtils.mkdir_p(Rails.root.join('tmp', 'exports'))
    
    # Write export data with error handling
    begin
      File.write(file_path, JSON.pretty_generate(export_data))
      Rails.logger.info "Export file created: #{file_path}"
    rescue StandardError => e
      Rails.logger.error "Failed to write export file: #{e.message}"
      raise
    end
    
    # Send notification email
    begin
      if admin_user
        # For future AdminMailer implementation
        Rails.logger.info "Admin export completed for user #{user.id} by admin #{admin_user.id}"
      else
        # Send to user via existing UserMailer
        UserMailer.data_export_ready(user, file_path.to_s).deliver_now
        Rails.logger.info "User export email sent to #{user.email}"
      end
    rescue StandardError => e
      Rails.logger.error "Failed to send export notification: #{e.message}"
      # Don't fail the job if email fails, file is still created
    end
    
    # Schedule file cleanup after 24 hours
    DeleteFileJob.set(wait: 24.hours).perform_later(file_path.to_s)
    
    Rails.logger.info "User export job completed for user_id: #{user_id}"
  rescue StandardError => e
    Rails.logger.error "UserExportJob failed for user_id #{user_id}: #{e.message}"
    raise
  end
  
  private
  
  def generate_user_export(user)
    {
      user_data: {
        id: user.id,
        email: user.email,
        first_name: user.first_name,
        last_name: user.last_name,
        timezone: user.timezone,
        marketing_emails: user.marketing_emails,
        created_at: user.created_at,
        updated_at: user.updated_at,
        confirmed_at: user.confirmed_at,
        sign_in_count: user.sign_in_count,
        current_sign_in_at: user.current_sign_in_at,
        last_sign_in_at: user.last_sign_in_at
      },
      subscription_data: {
        status: user.subscription&.status,
        created_at: user.subscription&.created_at,
        current_period_start: user.subscription&.current_period_start,
        current_period_end: user.subscription&.current_period_end
      },
      export_metadata: {
        generated_at: Time.current,
        export_type: 'full_account_data',
        version: '1.0'
      }
    }
  end
end