class Admin::SystemController < Admin::BaseController
  def index
    @system_health = get_comprehensive_system_health
    @sidekiq_stats = get_detailed_sidekiq_stats
    @database_stats = get_database_stats
    @redis_stats = get_redis_stats
    @application_stats = get_application_stats
  end
  
  private
  
  def get_comprehensive_system_health
    {
      database: check_database_health,
      redis: check_redis_health,
      sidekiq: check_sidekiq_health,
      disk_space: check_disk_space,
      memory_usage: get_memory_usage,
      uptime: get_application_uptime
    }
  end
  
  def check_database_health
    start_time = Time.current
    result = ActiveRecord::Base.connection.execute("SELECT 1")
    response_time = ((Time.current - start_time) * 1000).round(2)
    
    {
      status: result ? 'healthy' : 'error',
      response_time: response_time,
      connection_count: ActiveRecord::Base.connection_pool.connections.size,
      pool_size: ActiveRecord::Base.connection_pool.size
    }
  rescue => e
    {
      status: 'error',
      error: e.message,
      response_time: nil,
      connection_count: 0,
      pool_size: ActiveRecord::Base.connection_pool.size
    }
  end
  
  def check_redis_health
    start_time = Time.current
    redis = Redis.new
    result = redis.ping
    response_time = ((Time.current - start_time) * 1000).round(2)
    info = redis.info
    
    {
      status: result == "PONG" ? 'healthy' : 'error',
      response_time: response_time,
      memory_used: info['used_memory_human'],
      connected_clients: info['connected_clients'],
      commands_processed: info['total_commands_processed']
    }
  rescue => e
    {
      status: 'error',
      error: e.message,
      response_time: nil
    }
  end
  
  def check_sidekiq_health
    return { status: 'unavailable' } unless defined?(Sidekiq)
    
    stats = Sidekiq::Stats.new
    workers = Sidekiq::Workers.new
    
    {
      status: 'healthy',
      processed: stats.processed,
      failed: stats.failed,
      busy_workers: workers.size,
      enqueued: stats.enqueued,
      scheduled: stats.scheduled_size,
      retry_size: stats.retry_size,
      dead_size: stats.dead_size,
      default_queue_size: Sidekiq::Queue.new.size
    }
  rescue => e
    {
      status: 'error',
      error: e.message
    }
  end
  
  def check_disk_space
    begin
      if RUBY_PLATFORM.include?("linux") || RUBY_PLATFORM.include?("darwin")
        df_output = `df -h /`.lines.last
        parts = df_output.split
        {
          total: parts[1],
          used: parts[2],
          available: parts[3],
          percentage: parts[4]
        }
      else
        { status: 'unavailable', message: 'Disk space monitoring not available on this platform' }
      end
    rescue
      { status: 'error', message: 'Unable to retrieve disk space information' }
    end
  end
  
  def get_memory_usage
    begin
      if RUBY_PLATFORM.include?("linux")
        memory_info = File.read('/proc/meminfo')
        total_match = memory_info.match(/MemTotal:\s+(\d+) kB/)
        available_match = memory_info.match(/MemAvailable:\s+(\d+) kB/)
        
        if total_match && available_match
          total_mb = total_match[1].to_i / 1024
          available_mb = available_match[1].to_i / 1024
          used_mb = total_mb - available_mb
          percentage = ((used_mb.to_f / total_mb) * 100).round(1)
          
          {
            total: "#{total_mb} MB",
            used: "#{used_mb} MB",
            available: "#{available_mb} MB",
            percentage: "#{percentage}%"
          }
        else
          { status: 'unavailable' }
        end
      else
        { status: 'unavailable', message: 'Memory monitoring not available on this platform' }
      end
    rescue
      { status: 'error', message: 'Unable to retrieve memory information' }
    end
  end
  
  def get_application_uptime
    boot_time = Rails.application.config.beginning_of_time || Time.current
    uptime_seconds = Time.current - boot_time
    
    days = (uptime_seconds / 86400).floor
    hours = ((uptime_seconds % 86400) / 3600).floor
    minutes = ((uptime_seconds % 3600) / 60).floor
    
    "#{days}d #{hours}h #{minutes}m"
  rescue
    "Unknown"
  end
  
  def get_detailed_sidekiq_stats
    return {} unless defined?(Sidekiq)
    
    stats = Sidekiq::Stats.new
    queues = Sidekiq::Queue.all
    
    {
      overview: {
        processed: stats.processed,
        failed: stats.failed,
        busy: stats.processes_size,
        enqueued: stats.enqueued,
        scheduled: stats.scheduled_size,
        retry: stats.retry_size,
        dead: stats.dead_size
      },
      queues: queues.map do |queue|
        {
          name: queue.name,
          size: queue.size,
          latency: queue.latency.round(2)
        }
      end
    }
  rescue => e
    { error: e.message }
  end
  
  def get_database_stats
    {
      total_users: User.count,
      verified_users: User.where.not(confirmed_at: nil).count,
      total_subscriptions: Subscription.count,
      active_subscriptions: Subscription.where.not(status: 'canceled').count,
      admin_users: AdminUser.count,
      database_size: get_database_size
    }
  rescue => e
    { error: e.message }
  end
  
  def get_database_size
    result = ActiveRecord::Base.connection.execute(
      "SELECT pg_size_pretty(pg_database_size(current_database()));"
    )
    result.first['pg_size_pretty']
  rescue
    'Unknown'
  end
  
  def get_redis_stats
    redis = Redis.new
    info = redis.info
    
    {
      version: info['redis_version'],
      memory_used: info['used_memory_human'],
      memory_peak: info['used_memory_peak_human'],
      connected_clients: info['connected_clients'],
      total_commands: info['total_commands_processed'],
      keyspace_hits: info['keyspace_hits'],
      keyspace_misses: info['keyspace_misses']
    }
  rescue => e
    { error: e.message }
  end
  
  def get_application_stats
    {
      rails_version: Rails::VERSION::STRING,
      ruby_version: RUBY_VERSION,
      environment: Rails.env,
      timezone: Time.zone.name,
      total_routes: Rails.application.routes.routes.count,
      active_controllers: ApplicationController.descendants.count
    }
  end
end