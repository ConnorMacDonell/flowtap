class Admin::PasswordsController < Devise::PasswordsController
  layout 'admin_auth'
  
  protected
  
  def after_resetting_password_path_for(resource)
    admin_root_path
  end
end