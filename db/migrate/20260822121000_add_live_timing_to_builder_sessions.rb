class AddLiveTimingToBuilderSessions < ActiveRecord::Migration[8.1]
  def change
    change_table :builder_sessions, bulk: true do |t|
      t.datetime :builder_updates_started_at
      t.datetime :closing_started_at
      t.datetime :hangout_started_at
      t.datetime :ended_at
      t.string :finish_reason
    end

    change_table :builder_session_attendances, bulk: true do |t|
      t.integer :speaker_position
      t.string :speaker_state
      t.datetime :speaker_started_at
      t.datetime :speaker_ended_at
      t.integer :speaker_allotted_seconds
      t.integer :speaker_paused_seconds, null: false, default: 0
    end

    add_index :builder_session_attendances,
      [ :builder_session_id, :speaker_position ],
      unique: true,
      where: "speaker_position IS NOT NULL",
      name: "index_session_attendances_on_speaker_position"
    add_index :builder_session_attendances,
      :builder_session_id,
      unique: true,
      where: "speaker_state = 'speaking'",
      name: "index_session_attendances_on_current_speaker"
  end
end
