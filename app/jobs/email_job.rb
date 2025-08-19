class EmailJob < ApplicationJob
  queue_as :mailers
  
  retry_on StandardError, wait: :polynomially_longer, attempts: 3
  
  def perform(mailer_class, mailer_method, *args)
    # Handle different argument types for mailer methods
    if args.length == 1 && args.first.is_a?(Hash)
      # For methods like account_deleted that take a hash
      mailer_class.constantize.send(mailer_method, args.first).deliver_now
    elsif args.length >= 1 && args.first.is_a?(Integer)
      # For methods that take a user ID as first argument
      user = User.find(args.first)
      remaining_args = args[1..-1]
      mailer_class.constantize.send(mailer_method, user, *remaining_args).deliver_now
    else
      # For other method signatures
      mailer_class.constantize.send(mailer_method, *args).deliver_now
    end
  rescue => e
    Rails.logger.error "EmailJob failed: #{e.message}"
    Rails.logger.error "Mailer: #{mailer_class}##{mailer_method}, Args: #{args.inspect}"
    raise e
  end
end