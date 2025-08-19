class ErrorsController < ApplicationController
  skip_before_action :authenticate_user!
  
  def not_found
    respond_to do |format|
      format.html { render status: 404 }
      format.json { render json: { error: 'Not Found' }, status: 404 }
    end
  end

  def internal_server_error
    respond_to do |format|
      format.html { render status: 500 }
      format.json { render json: { error: 'Internal Server Error' }, status: 500 }
    end
  end

  def unprocessable_entity
    respond_to do |format|
      format.html { render status: 422 }
      format.json { render json: { error: 'Unprocessable Entity' }, status: 422 }
    end
  end
end