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
      # Record EULA and Privacy Policy acceptance timestamps
      resource.update!(
        eula_accepted_at: Time.current,
        privacy_policy_accepted_at: Time.current
      )

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
    devise_parameter_sanitizer.permit(:sign_up, keys: [:first_name, :last_name, :timezone, :eula_accepted, :password, :password_confirmation])
  end

  # If you have extra params to permit, append them to the sanitizer.
  def configure_account_update_params
    devise_parameter_sanitizer.permit(:account_update, keys: [:first_name, :last_name, :timezone, :marketing_emails, :password, :password_confirmation, :current_password])
  end

  # The path used after sign up.
  def after_sign_up_path_for(resource)
    if resource.persisted?
      flash[:notice] = "Welcome! Please check your email to confirm your account and complete your subscription."
      create_checkout_session_url(resource)
    else
      new_user_registration_path
    end
  end

  # The path used after sign up for inactive accounts.
  def after_inactive_sign_up_path_for(resource)
    flash[:notice] = "Please check your email to confirm your account and complete your subscription."
    create_checkout_session_url(resource)
  end

  private

  def create_checkout_session_url(user)
    checkout_service = StripeCheckoutService.new(
      user,
      success_url: success_subscriptions_url,
      cancel_url: cancel_payment_subscriptions_url
    )

    checkout_url = checkout_service.create_checkout_session

    # Fallback to dashboard if Stripe checkout fails
    checkout_url || dashboard_url
  end

end