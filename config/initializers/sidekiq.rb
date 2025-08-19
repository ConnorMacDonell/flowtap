# Sidekiq configuration
Sidekiq.configure_server do |config|
  config.redis = { 
    url: ENV.fetch("REDIS_URL", "redis://localhost:6379/0"),
    network_timeout: 5,
    pool_timeout: 5
  }
  
  # Configure concurrency based on environment
  config.concurrency = ENV.fetch("SIDEKIQ_CONCURRENCY", Rails.env.production? ? 5 : 2).to_i
  
  # Configure queues with priority (higher priority = processed first)
  config.queues = %w[critical default mailers low]
  
  # Add middleware for job tracking and error handling
  config.server_middleware do |chain|
    # Add unique job middleware to prevent duplicate jobs
    chain.add Sidekiq::Middleware::Server::RetryJobs
    
    # Add logging middleware for production debugging
    if Rails.env.production?
      chain.add Sidekiq::Middleware::Server::Logging
    end
  end
  
  # Client middleware for job enqueueing
  config.client_middleware do |chain|
    # Add logging for job creation in development
    if Rails.env.development?
      chain.add Sidekiq::Middleware::Client::Logging
    end
  end
  
  # Configure death handlers for failed jobs
  config.death_handlers << lambda do |job, ex|
    Rails.logger.error "Job #{job['class']} failed permanently: #{ex.message}"
    
    # Optionally notify admin of critical job failures
    if job['queue'] == 'critical'
      # AdminMailer.job_failure_notification(job, ex).deliver_now
    end
  end
end

Sidekiq.configure_client do |config|
  config.redis = { 
    url: ENV.fetch("REDIS_URL", "redis://localhost:6379/0"),
    network_timeout: 5,
    pool_timeout: 5
  }
end

# Configure default job options with improved retry logic
Sidekiq.default_job_options = {
  'retry' => 5,
  'backtrace' => true,
  'queue' => 'default',
  'dead' => true,
  'unique_for' => 1.hour # Prevent duplicate jobs within 1 hour
}

# Configure specific retry logic for different types of jobs
Sidekiq.configure_server do |config|
  # Custom retry logic for different job types
  config.error_handlers << lambda do |ex, ctx|
    Rails.logger.error "Sidekiq job error: #{ex.message}"
    Rails.logger.error "Job context: #{ctx}"
    
    # Log specific details about the failed job
    job = ctx[:job] || {}
    Rails.logger.error "Failed job: #{job['class']} with args: #{job['args']}"
  end
end

# Configure logger with appropriate level
if Rails.env.production?
  Sidekiq.logger.level = Logger::WARN
else
  Sidekiq.logger.level = Logger::DEBUG
end