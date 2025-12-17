class OwnersController < ApplicationController
  before_action :authenticate_user!
  before_action :require_admin!, only: :dashboard

  def dashboard
    redirect_to dashboard_path
  end
end
