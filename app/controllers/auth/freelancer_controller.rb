class Auth::FreelancerController < ApplicationController
  skip_before_action :authenticate_user!, only: [:authorize]
  skip_before_action :verify_authenticity_token, only: [:authorize]
  
  def authorize
    render json: { status: 'success', message: 'Authorization callback received' }, status: :ok
  end
end