class AddSessionCancellations < ActiveRecord::Migration[8.1]
  def change
    change_table :builder_sessions do |t|
      t.text :source_calendar_id
      t.datetime :cancellation_requested_at
      t.text :cancellation_reason
      t.datetime :cancellation_calendar_deleted_at
      t.datetime :cancellation_completed_at
      t.datetime :cancellation_claimed_at
    end

    create_table :session_cancellation_deliveries do |t|
      t.references :builder_session, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.datetime :sent_at
      t.datetime :skipped_at
      t.datetime :first_attempted_at
      t.timestamps
    end
    add_index :session_cancellation_deliveries, [ :builder_session_id, :user_id ], unique: true
  end
end
