class MetricsCalculationJob < ApplicationJob
  queue_as :low
  retry_on StandardError, wait: :polynomially_longer, attempts: 3
  
  def perform(calculation_type = 'daily')
    Rails.logger.info "Starting metrics calculation: #{calculation_type}"
    
    case calculation_type
    when 'daily'
      calculate_daily_metrics
    when 'weekly'
      calculate_weekly_metrics
    when 'monthly'
      calculate_monthly_metrics
    when 'all'
      calculate_daily_metrics
      calculate_weekly_metrics
      calculate_monthly_metrics
    else
      Rails.logger.warn "Unknown calculation type: #{calculation_type}"
      return
    end
    
    Rails.logger.info "Metrics calculation completed: #{calculation_type}"
  rescue StandardError => e
    Rails.logger.error "MetricsCalculationJob failed for #{calculation_type}: #{e.message}"
    raise
  end
  
  private
  
  def calculate_daily_metrics
    today = Date.current
    yesterday = today - 1.day
    
    metrics = {
      date: today,
      total_users: User.count,
      verified_users: User.where.not(confirmed_at: nil).count,
      new_signups_today: User.where(created_at: today.beginning_of_day..today.end_of_day).count,
      new_signups_yesterday: User.where(created_at: yesterday.beginning_of_day..yesterday.end_of_day).count,
      subscription_tiers: calculate_subscription_metrics,
      active_sessions: calculate_active_sessions,
      system_health: calculate_system_health
    }
    
    # Store metrics in cache for dashboard
    Rails.cache.write("daily_metrics_#{today}", metrics, expires_in: 25.hours)
    
    Rails.logger.info "Daily metrics calculated: #{metrics[:new_signups_today]} new signups today"
  end
  
  def calculate_weekly_metrics
    current_week = Date.current.beginning_of_week
    weeks_data = []
    
    8.times do |i|
      week_start = current_week - i.weeks
      week_end = week_start.end_of_week
      
      week_signups = User.where(created_at: week_start..week_end).count
      weeks_data << {
        week_start: week_start,
        signups: week_signups
      }
    end
    
    # Store weekly trends in cache
    Rails.cache.write('weekly_signup_trends', weeks_data.reverse, expires_in: 25.hours)
    
    Rails.logger.info "Weekly metrics calculated for last 8 weeks"
  end
  
  def calculate_monthly_metrics
    current_month = Date.current.beginning_of_month
    
    metrics = {
      month: current_month,
      total_revenue: calculate_monthly_revenue,
      new_customers: User.joins(:subscription)
                         .where(users: { created_at: current_month..Date.current.end_of_month })
                         .where.not(subscriptions: { status: 'free' })
                         .count,
      churn_rate: calculate_churn_rate,
      conversion_rate: calculate_conversion_rate
    }
    
    Rails.cache.write("monthly_metrics_#{current_month.strftime('%Y_%m')}", metrics, expires_in: 30.days)
    
    Rails.logger.info "Monthly metrics calculated: #{metrics[:new_customers]} new paying customers"
  end
  
  def calculate_subscription_metrics
    {
      free: Subscription.where(status: 'free').count,
      standard: Subscription.where(status: 'standard').count,
      premium: Subscription.where(status: 'premium').count,
      total_paid: Subscription.where.not(status: 'free').count
    }
  end
  
  def calculate_active_sessions
    # Calculate users who signed in within the last 24 hours
    User.where(current_sign_in_at: 24.hours.ago..Time.current).count
  end
  
  def calculate_system_health
    {
      database_status: check_database_health,
      redis_status: check_redis_health,
      sidekiq_queue_sizes: get_sidekiq_queue_sizes,
      calculated_at: Time.current
    }
  end
  
  def calculate_monthly_revenue
    # This would integrate with Stripe API to get actual revenue
    # For now, estimate based on subscription counts
    standard_count = Subscription.where(status: 'standard').count
    premium_count = Subscription.where(status: 'premium').count
    
    (standard_count * 19) + (premium_count * 49)
  end
  
  def calculate_churn_rate
    # Calculate monthly churn rate
    current_month = Date.current.beginning_of_month
    last_month = current_month - 1.month
    
    canceled_this_month = Subscription.where(canceled_at: current_month..Date.current.end_of_month).count
    active_last_month = Subscription.where(created_at: ..last_month.end_of_month)
                                  .where.not(status: 'free').count
    
    return 0 if active_last_month.zero?
    
    (canceled_this_month.to_f / active_last_month * 100).round(2)
  end
  
  def calculate_conversion_rate
    # Calculate free to paid conversion rate over last 30 days
    thirty_days_ago = 30.days.ago
    
    new_users = User.where(created_at: thirty_days_ago..Time.current).count
    converted_users = User.joins(:subscription)
                         .where(users: { created_at: thirty_days_ago..Time.current })
                         .where.not(subscriptions: { status: 'free' })
                         .count
    
    return 0 if new_users.zero?
    
    (converted_users.to_f / new_users * 100).round(2)
  end
  
  def check_database_health
    begin
      ActiveRecord::Base.connection.execute('SELECT 1')
      'healthy'
    rescue
      'unhealthy'
    end
  end
  
  def check_redis_health
    begin
      Redis.current.ping == 'PONG' ? 'healthy' : 'unhealthy'
    rescue
      'unhealthy'
    end
  end
  
  def get_sidekiq_queue_sizes
    {
      critical: Sidekiq::Queue.new('critical').size,
      default: Sidekiq::Queue.new('default').size,
      mailers: Sidekiq::Queue.new('mailers').size,
      low: Sidekiq::Queue.new('low').size
    }
  rescue
    { error: 'Unable to fetch queue sizes' }
  end
end