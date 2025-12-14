class AddDataToRiskAssistants < ActiveRecord::Migration[7.0]
  def change
    add_column :risk_assistants, :data, :jsonb, default: {}
    add_index :risk_assistants, :data, using: :gin
  end
end
