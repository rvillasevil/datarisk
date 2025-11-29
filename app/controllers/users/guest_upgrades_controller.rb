class Users::GuestUpgradesController < ApplicationController
  before_action :authenticate_user!

  def create
    unless current_user.guest?
      redirect_to after_sign_in_path_for(current_user), alert: 'Solo las cuentas invitadas pueden convertirse en usuarios normales.'
      return
    end

    if current_user.update(role: :client, owner_id: nil)
      redirect_to after_sign_in_path_for(current_user), notice: 'Tu cuenta ahora es un usuario normal con su propio dashboard.'
    else
      redirect_to after_sign_in_path_for(current_user), alert: current_user.errors.full_messages.to_sentence
    end
  end
end