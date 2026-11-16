class CreateWeeklyCherryDeliveries < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :weekly_cherry_notifications, :boolean, default: true, null: false
    add_column :builder_session_transcripts, :weekly_cherry_queued_at, :datetime

    create_table :weekly_cherry_deliveries do |t|
      t.references :builder_session_transcript, null: false, foreign_key: true, index: false
      t.references :user, null: false, foreign_key: true
      t.boolean :summary, default: false, null: false
      t.text :copy
      t.datetime :first_attempted_at
      t.datetime :sent_at
      t.datetime :skipped_at
      t.datetime :failed_at
      t.timestamps

      t.index [ :builder_session_transcript_id, :user_id, :summary ], unique: true, name: "index_weekly_cherry_deliveries_on_recipient"
      t.index :builder_session_transcript_id, unique: true, where: "summary = TRUE", name: "index_weekly_cherry_deliveries_on_summary"
      t.index :id, where: "sent_at IS NULL AND skipped_at IS NULL AND failed_at IS NULL", name: "index_weekly_cherry_deliveries_pending"
    end
  end
end
