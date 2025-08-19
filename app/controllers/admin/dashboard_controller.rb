class Admin::DashboardController < Admin::BaseController
  def index
    @total_users = User.count
    @verified_users = User.where.not(confirmed_at: nil).count
    @unverified_users = User.where(confirmed_at: nil).count
    @deleted_users = User.where.not(deleted_at: nil).count
    
    # Subscription metrics
    @subscription_stats = {
      free: User.joins(:subscription).where(subscriptions: { status: 'free' }).count,
      standard: User.joins(:subscription).where(subscriptions: { status: 'standard' }).count,
      premium: User.joins(:subscription).where(subscriptions: { status: 'premium' }).count
    }
    
    # Recent activity (last 30 days)
    thirty_days_ago = 30.days.ago
    @new_users_this_month = User.where(created_at: thirty_days_ago..Time.current).count
    @recent_signups = User.where(created_at: thirty_days_ago..Time.current)
                         .order(created_at: :desc)
                         .limit(10)
    
    # System health
    @system_health = {
      database: check_database_connection,
      redis: check_redis_connection,
      sidekiq_queues: get_sidekiq_stats
    }
    
    # Weekly signup chart data (last 8 weeks)
    @weekly_signups = (0..7).map do |weeks_ago|
      start_date = weeks_ago.weeks.ago.beginning_of_week
      end_date = start_date.end_of_week
      {
        week: start_date.strftime("%m/%d"),
        count: User.where(created_at: start_date..end_date).count
      }
    end.reverse
  end
  
  private
  
  def check_database_connection
    ActiveRecord::Base.connection.active?
  rescue
    false
  end
  
  def check_redis_connection
    Redis.new.ping == "PONG"
  rescue
    false
  end
  
  def get_sidekiq_stats
    return { total: 0, failed: 0 } unless defined?(Sidekiq)
    
    stats = Sidekiq::Stats.new
    {
      total: stats.processed,
      failed: stats.failed,
      enqueued: stats.enqueued,
      scheduled: stats.scheduled_size,
      retry: stats.retry_size,
      dead: stats.dead_size
    }
  rescue
    { total: 0, failed: 0, enqueued: 0, scheduled: 0, retry: 0, dead: 0 }
  end
end