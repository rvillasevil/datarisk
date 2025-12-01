class OwnersController < ApplicationController
  before_action :authenticate_user!
  before_action :require_owner!

  def dashboard; end

  private

  def require_owner!
    redirect_to(root_path, alert: 'Solo los owners pueden acceder.') unless current_user&.owner?
  end
end