class AddGuestTokenToRiskAssistants < ActiveRecord::Migration[7.0]
  def change
    add_column :risk_assistants, :guest_token, :string
    add_index :risk_assistants, :guest_token
  end
end
