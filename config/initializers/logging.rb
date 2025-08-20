# Structured logging configuration

# Custom log formatter for better structure
class StructuredLogFormatter < Logger::Formatter
  def call(severity, time, progname, msg)
    log_entry = {
      timestamp: time.utc.iso8601,
      severity: severity,
      progname: progname,
      message: msg.is_a?(String) ? msg : msg.inspect,
      environment: Rails.env,
      application: Rails.application.class.module_parent_name.downcase
    }
    
    # Add request ID if available
    if Thread.current[:request_id]
      log_entry[:request_id] = Thread.current[:request_id]
    end
    
    "#{JSON.generate(log_entry)}\n"
  end
end

# Apply structured logging in production
# Temporarily disabled due to TaggedLogging conflicts
# if Rails.env.production?
#   Rails.logger.formatter = StructuredLogFormatter.new
# end

# Configure log rotation in production
# Temporarily disabled due to TaggedLogging conflicts
# if Rails.env.production?
#   Rails.application.configure do
#     # Rotate logs daily, keep 7 days worth
#     config.logger = ActiveSupport::Logger.new(
#       Rails.root.join('log', 'production.log'),
#       1, # Keep 1 old log file
#       100.megabytes # Max size before rotation
#     )
#     config.logger.formatter = StructuredLogFormatter.new
#   end
# end

# Add request ID tracking middleware
Rails.application.config.middleware.insert_before(
  ActionDispatch::RequestId,
  Class.new do
    def initialize(app)
      @app = app
    end
    
    def call(env)
      Thread.current[:request_id] = env['action_dispatch.request_id']
      @app.call(env)
    ensure
      Thread.current[:request_id] = nil
    end
  end
)

# Custom logging methods for different levels
module CustomLogging
  def log_info(message, context = {})
    Rails.logger.info(format_log_message(message, context))
  end
  
  def log_warn(message, context = {})
    Rails.logger.warn(format_log_message(message, context))
  end
  
  def log_error(message, context = {})
    Rails.logger.error(format_log_message(message, context))
  end
  
  def log_security(message, context = {})
    context[:security_event] = true
    Rails.logger.warn(format_log_message("[SECURITY] #{message}", context))
  end
  
  private
  
  def format_log_message(message, context)
    if context.any?
      "#{message} | Context: #{context.to_json}"
    else
      message
    end
  end
end

# Include custom logging in controllers and jobs
ActionController::Base.include CustomLogging
ActiveJob::Base.include CustomLogging