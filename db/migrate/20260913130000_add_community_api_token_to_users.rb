class AddCommunityApiTokenToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :community_api_token_digest, :string
    add_column :users, :community_api_token_generated_at, :datetime
    add_index :users, :community_api_token_digest, unique: true
  end
end
