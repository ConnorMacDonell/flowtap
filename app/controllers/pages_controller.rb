class PagesController < ApplicationController
  skip_before_action :authenticate_user!, only: [:eula, :privacy]

  def eula
    # Display EULA page
  end

  def privacy
    # Display Privacy Policy page
  end
end
