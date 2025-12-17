class InvitationsController < ApplicationController
  def accept
    invitation = ClientInvitation.find_by!(token: params[:token])    
    redirect_to new_token_session_path(token: invitation.token)
  end
end
