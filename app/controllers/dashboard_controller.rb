class DashboardController < ApplicationController
  before_action :authenticate_user!

  def show
    @risk_assistants = risk_assistants_scope.order(updated_at: :desc)
    @client_invitations = current_user.admin? ? current_user.client_invitations.order(created_at: :desc) : ClientInvitation.none
  end
end
