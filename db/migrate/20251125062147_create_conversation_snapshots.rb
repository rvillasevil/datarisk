class CreateConversationSnapshots < ActiveRecord::Migration[7.0]
  def change
    create_table :conversation_snapshots do |t|
      t.references :risk_assistant, null: false, foreign_key: true
      t.string :thread_id
      t.text :last_user_message
      t.text :last_assistant_message
      t.jsonb :messages_dump, default: []
      t.jsonb :normalized_payload, default: {}
      t.string :status, default: "captured", null: false

      t.timestamps
    end

    add_index :conversation_snapshots, :thread_id
  end
end