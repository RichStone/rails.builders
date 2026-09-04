class AddNotesAndAnalysisToBuilderSessionTranscripts < ActiveRecord::Migration[8.1]
  def change
    add_column :builder_session_transcripts, :summary_notes, :text
    add_column :builder_session_transcripts, :session_analysis, :text
  end
end
