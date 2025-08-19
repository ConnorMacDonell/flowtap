class HomeController < ApplicationController
  skip_before_action :authenticate_user!
  
  def index
    # Landing page for the SaaS application
  end
end