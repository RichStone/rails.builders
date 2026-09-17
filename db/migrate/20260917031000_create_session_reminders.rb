class CreateSessionReminders < ActiveRecord::Migration[8.1]
  def change
    create_table :session_reminders do |t|
      t.references :user, null: false, foreign_key: true
      t.references :builder_session, null: false, foreign_key: true
      t.datetime :scheduled_starts_at, null: false
      t.datetime :sent_at
      t.timestamps
    end

    add_index :session_reminders, %i[user_id builder_session_id scheduled_starts_at], unique: true
  end
end
