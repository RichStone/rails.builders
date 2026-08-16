class AddTokenVersionsToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :sign_in_token_version, :integer, null: false, default: 0
    add_column :users, :newsletter_token_version, :integer, null: false, default: 0
  end
end
