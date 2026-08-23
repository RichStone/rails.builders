class AddPublicProfileApprovedToUsers < ActiveRecord::Migration[8.1]
  def up
    add_column :users, :public_profile_approved, :boolean, null: false, default: false
    execute <<~SQL.squish
      UPDATE users
      SET public_profile_approved = 1
      WHERE public_profile = 1 AND facilitator = 1
    SQL
  end

  def down
    remove_column :users, :public_profile_approved
  end
end
