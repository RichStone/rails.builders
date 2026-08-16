class AddClickfunnelsPublicIdToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :clickfunnels_contact_public_id, :string
  end
end
