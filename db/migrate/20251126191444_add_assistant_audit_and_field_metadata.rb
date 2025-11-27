class AddAssistantAuditAndFieldMetadata < ActiveRecord::Migration[7.0]
  def change
    create_table :assistant_run_logs do |t|
      t.references :risk_assistant, null: false, foreign_key: true
      t.string :run_id
      t.string :endpoint, null: false
      t.jsonb :request_payload, null: false, default: {}
      t.jsonb :response_payload, null: false, default: {}
      t.integer :http_status
      t.timestamps
    end

    add_index :assistant_run_logs, [:risk_assistant_id, :run_id]
    add_index :assistant_run_logs, [:risk_assistant_id, :endpoint]

    add_column :messages, :value_state, :string
    add_column :messages, :value_source, :string
    add_index :messages, [:risk_assistant_id, :field_asked, :created_at], name: "index_messages_on_assistant_field_created_at"

    add_column :risk_assistants, :field_catalog_version, :string
  end
end
