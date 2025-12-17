class AddUserToClientInvitations < ActiveRecord::Migration[7.0]
  def change
    add_reference :client_invitations, :user, foreign_key: true, null: true
  end
end

