class Users::RegistrationsController < Devise::RegistrationsController
  before_action :configure_sign_up_params, only: [:create]
  before_action :configure_account_update_params, only: [:update]
  skip_before_action :authenticate_user!, only: [:new, :create]

  # GET /resource/sign_up
  def new
    super
  end

  # POST /resource
  def create
    build_resource(sign_up_params)

    resource.save
    yield resource if block_given?
    if resource.persisted?
      # Create initial subscription record for tracking
      resource.create_subscription!(status: 'inactive') unless resource.subscription
      
      # Create Stripe customer for payment processing
      ensure_stripe_customer!(resource)
      
      if resource.active_for_authentication?
        set_flash_message! :notice, :signed_up
        sign_up(resource_name, resource)
        redirect_to after_sign_up_path_for(resource), allow_other_host: true
      else
        set_flash_message! :notice, :"signed_up_but_#{resource.inactive_message}"
        expire_data_after_sign_in!
        redirect_to after_inactive_sign_up_path_for(resource), allow_other_host: true
      end
    else
      clean_up_passwords resource
      set_minimum_password_length
      respond_with resource
    end
  end

  # GET /resource/edit
  def edit
    super
  end

  # PUT /resource
  def update
    super
  end

  # DELETE /resource
  def destroy
    # Store user data for email before soft delete
    user_data = {
      name: resource.full_name,
      email: resource.email,
      deleted_at: Time.current
    }
    
    # Implement soft delete instead of hard delete
    resource.soft_delete!
    
    # Send account deletion email
    UserMailer.account_deleted(user_data).deliver_now
    # TODO use background job
    # EmailJob.perform_later('UserMailer', 'account_deleted', user_data)
    
    Devise.sign_out_all_scopes ? sign_out : sign_out(resource_name)
    set_flash_message! :notice, :destroyed
    yield resource if block_given?
    respond_with_navigational(resource){ redirect_to after_sign_out_path_for(resource_name) }
  end

  # GET /resource/cancel
  # Forces the session data which is usually expired after sign
  # in to be expired now. This is useful if the user wants to
  # cancel oauth signing in/up in the middle of the process,
  # removing all OAuth session data.
  def cancel
    super
  end

  protected

  # If you have extra params to permit, append them to the sanitizer.
  def configure_sign_up_params
    devise_parameter_sanitizer.permit(:sign_up, keys: [:first_name, :last_name, :timezone, :marketing_emails])
  end

  # If you have extra params to permit, append them to the sanitizer.
  def configure_account_update_params
    devise_parameter_sanitizer.permit(:account_update, keys: [:first_name, :last_name, :timezone, :marketing_emails])
  end

  # The path used after sign up.
  def after_sign_up_path_for(resource)
    if resource.persisted?
      flash[:notice] = "Welcome! Please check your email to confirm your account and complete your subscription."
      stripe_payment_link
    else
      new_user_registration_path
    end
  end

  # The path used after sign up for inactive accounts.
  def after_inactive_sign_up_path_for(resource)
    flash[:notice] = "Please check your email to confirm your account and complete your subscription."
    stripe_payment_link
  end

  private

  def stripe_payment_link
    # Build Stripe payment link with success URL back to our app
    base_url = ENV['STRIPE_PAYMENT_LINK'] || 'https://buy.stripe.com/test_placeholder'
    success_url = "#{request.base_url}/subscriptions/success"
    "#{base_url}?success_url=#{CGI.escape(success_url)}"
  end

  def ensure_stripe_customer!(user)
    return if user.stripe_customer_id.present?

    begin
      customer = Stripe::Customer.create(
        email: user.email,
        name: "#{user.first_name} #{user.last_name}".strip,
        metadata: {
          user_id: user.id
        }
      )
      user.update!(stripe_customer_id: customer.id)
    rescue Stripe::StripeError => e
      Rails.logger.error "Failed to create Stripe customer: #{e.message}"
      # Don't fail signup if Stripe is down, customer can be created later
    end
  end
end