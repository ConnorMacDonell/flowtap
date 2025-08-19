class Admin::BaseController < ApplicationController
  before_action :authenticate_admin_user!
  
  layout 'admin'
  
  private
  
  def authenticate_admin_user!
    unless admin_user_signed_in?
      redirect_to new_admin_user_session_path, alert: "Please sign in as an administrator to access this page."
    end
  end
end