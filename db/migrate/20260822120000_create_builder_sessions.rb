class CreateBuilderSessions < ActiveRecord::Migration[8.1]
  def change
    add_reference :programs, :main_facilitator, foreign_key: { to_table: :users }

    create_table :builder_sessions do |t|
      t.references :program, null: false, foreign_key: true
      t.references :assigned_facilitator, foreign_key: { to_table: :users }
      t.string :google_event_id, null: false
      t.string :title, null: false
      t.text :description
      t.string :location
      t.string :meet_url
      t.string :time_zone, null: false
      t.datetime :scheduled_starts_at, null: false
      t.datetime :scheduled_ends_at, null: false
      t.string :state, null: false, default: "ready"
      t.integer :timer_duration_seconds
      t.string :facilitator_name_snapshot
      t.datetime :started_at

      t.timestamps
    end

    add_index :builder_sessions, [ :program_id, :google_event_id ], unique: true
    add_index :builder_sessions, [ :program_id, :state, :scheduled_starts_at ]
    add_index :builder_sessions,
      :program_id,
      unique: true,
      where: "state IN ('connection', 'builder_updates', 'closing', 'hangout')",
      name: "index_builder_sessions_on_one_active_program"

    create_table :builder_session_attendances do |t|
      t.references :builder_session, null: false, foreign_key: true
      t.references :user, foreign_key: true
      t.string :display_name, null: false
      t.string :role, null: false
      t.string :status, null: false, default: "absent"
      t.datetime :arrived_at

      t.timestamps
    end

    add_index :builder_session_attendances,
      [ :builder_session_id, :user_id ],
      unique: true,
      where: "user_id IS NOT NULL",
      name: "index_session_attendances_on_session_and_user"
  end
end
