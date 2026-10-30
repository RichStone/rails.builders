class AddCalendarNotesToBuilderSessionTranscripts < ActiveRecord::Migration[8.1]
  def change
    add_column :builder_session_transcripts, :calendar_notes, :text
    add_column :builder_session_transcripts, :calendar_notes_synced_at, :datetime
    add_column :builder_session_transcripts, :calendar_notes_attempted_at, :datetime
    add_column :builder_session_transcripts, :calendar_notes_next_attempt_at, :datetime
    add_column :builder_session_transcripts, :calendar_notes_error_code, :string
    add_index :builder_session_transcripts, :calendar_notes_next_attempt_at
  end
end
