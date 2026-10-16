class CreateLoginSessions < ActiveRecord::Migration[8.1]
  def change
    create_table :login_sessions do |t|
      t.references :user, null: false, foreign_key: true
      t.timestamps
    end
    add_index :login_sessions, :created_at
  end
end
