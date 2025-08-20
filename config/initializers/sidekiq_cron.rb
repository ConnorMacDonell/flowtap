# Scheduled jobs configuration using sidekiq-cron
if defined?(Sidekiq::Cron::Job) && ENV['REDIS_URL'].present?
  # Only load scheduled jobs in production and staging environments
  if Rails.env.production? || Rails.env.staging?
    begin
    
    # Daily metrics calculation at 1 AM
    Sidekiq::Cron::Job.load_from_hash({
      'daily_metrics' => {
        'cron' => '0 1 * * *',
        'class' => 'MetricsCalculationJob',
        'args' => ['daily'],
        'queue' => 'low'
      }
    })
    
    # Weekly metrics calculation on Sundays at 2 AM
    Sidekiq::Cron::Job.load_from_hash({
      'weekly_metrics' => {
        'cron' => '0 2 * * 0',
        'class' => 'MetricsCalculationJob',
        'args' => ['weekly'],
        'queue' => 'low'
      }
    })
    
    # Monthly metrics calculation on the 1st of each month at 3 AM
    Sidekiq::Cron::Job.load_from_hash({
      'monthly_metrics' => {
        'cron' => '0 3 1 * *',
        'class' => 'MetricsCalculationJob',
        'args' => ['monthly'],
        'queue' => 'low'
      }
    })
    
    # Daily cleanup at 4 AM
    Sidekiq::Cron::Job.load_from_hash({
      'daily_cleanup' => {
        'cron' => '0 4 * * *',
        'class' => 'DataCleanupJob',
        'args' => ['daily'],
        'queue' => 'low'
      }
    })
    
    # Weekly cleanup on Sundays at 5 AM
    Sidekiq::Cron::Job.load_from_hash({
      'weekly_cleanup' => {
        'cron' => '0 5 * * 0',
        'class' => 'DataCleanupJob',
        'args' => ['weekly'],
        'queue' => 'low'
      }
    })
    
    # Monthly cleanup on the 1st of each month at 6 AM
    Sidekiq::Cron::Job.load_from_hash({
      'monthly_cleanup' => {
        'cron' => '0 6 1 * *',
        'class' => 'DataCleanupJob',
        'args' => ['monthly'],
        'queue' => 'low'
      }
    })
    
      Rails.logger.info "Loaded #{Sidekiq::Cron::Job.all.count} scheduled jobs"
    rescue => e
      Rails.logger.error "Failed to load scheduled jobs: #{e.message}"
    end
  else
    Rails.logger.info "Skipping scheduled jobs in #{Rails.env} environment"
  end
end