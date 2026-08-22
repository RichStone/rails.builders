class CreateProgramCalendarConnections < ActiveRecord::Migration[8.1]
  def change
    create_table :program_calendar_connections do |t|
      t.references :program, null: false, foreign_key: true, index: { unique: true }
      t.references :facilitator, null: false, foreign_key: { to_table: :users }
      t.string :google_account_email, null: false
      t.string :google_calendar_id, null: false
      t.string :google_calendar_name, null: false
      t.string :google_calendar_time_zone
      t.string :google_data_owner
      t.text :oauth_token_json, null: false
      t.string :status, null: false, default: "connected"
      t.datetime :last_synced_at
      t.string :last_error_code

      t.timestamps
    end
  end
end
