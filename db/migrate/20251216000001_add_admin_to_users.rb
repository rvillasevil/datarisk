class AddAdminToUsers < ActiveRecord::Migration[7.0]
  def up
    add_column :users, :admin, :boolean, default: false, null: false

    # Backfill: el usuario owner existente se marca como admin
    execute <<~SQL
      UPDATE users
      SET admin = TRUE
      WHERE role = 0
    SQL
  end

  def down
    remove_column :users, :admin
  end
end
