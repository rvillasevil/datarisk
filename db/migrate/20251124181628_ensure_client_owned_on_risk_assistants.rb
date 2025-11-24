class EnsureClientOwnedOnRiskAssistants < ActiveRecord::Migration[7.0]
  def change
    unless column_exists?(:risk_assistants, :client_owned)
      add_column :risk_assistants, :client_owned, :boolean, default: false, null: false
    end

    unless index_exists?(:risk_assistants, :user_id, name: "index_risk_assistants_on_user_id_unique_for_client")
      add_index :risk_assistants, :user_id,
                unique: true,
                where: "client_owned",
                name: "index_risk_assistants_on_user_id_unique_for_client"
    end
  end
end