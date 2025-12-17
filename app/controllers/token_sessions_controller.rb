class TokenSessionsController < ApplicationController
  def new
    @token = params[:token].to_s.strip
  end

  def create
    token = params[:token].to_s.strip

    if token.blank?
      redirect_to new_token_session_path, alert: 'Introduce un token.'
      return
    end

    invitation = ClientInvitation.find_by(token: token)

    unless invitation
      redirect_to new_token_session_path, alert: 'Token inválido.'
      return
    end

    user = invitation.user

    unless user
      email = invitation.email.presence || "guest+#{invitation.token}@insurai.local"
      password = Devise.friendly_token.first(20)

      user = User.create!(
        email: email,
        name: 'Invitado',
        owner_id: invitation.owner_id,
        role: :guest,
        password: password,
        password_confirmation: password
      )

      invitation.update!(user: user, accepted_at: Time.current)
    end

    sign_in(:user, user)
    redirect_to dashboard_path, notice: 'Acceso concedido.'
  end
end
