class ClientsController < ApplicationController
  before_action :authenticate_user!
  before_action :require_admin!, only: %i[index new create destroy]
  before_action :set_user, except: :show
  before_action :set_client, only: %i[destroy show]

  def index
    @clients = @user.clients
    @client_invitations = @user.client_invitations.order(created_at: :desc)
  end

  def show; end

  def new
    @client = User.new
  end

  def create
    return redirect_to(user_clients_path(@user), alert: 'Client limit reached.') unless current_user.can_add_client?

    invitation = ClientInvitation.create(
      email: client_params[:email].presence,
      owner: current_user,
      token: client_params[:token].presence || SecureRandom.hex(10)
    )

    if send_invitation_email?(invitation)
      ClientInvitationMailer.with(invitation: invitation).invite.deliver_now
      notice = 'Invitation sent.'
    else
      notice = 'Token generated.'
    end

    redirect_to user_clients_path(@user), notice: notice 
  end

  def destroy
    @client.destroy
    @client.update(inactive: true) unless @client.destroyed?
    redirect_to user_clients_path(@user), notice: 'Client was revoked.'
  end

  def dashboard
    redirect_to dashboard_path
  end  

  private

  def set_user
    @user = current_user
  end

  def set_client
    @client = (@user || current_user).clients.find(params[:id])
  end

  def client_params
    params.require(:user).permit(:email, :token)
  end

  def send_invitation_email?(invitation)
    return false unless invitation.email.present?

    ActiveModel::Type::Boolean.new.cast(params[:send_email])
  end
end
