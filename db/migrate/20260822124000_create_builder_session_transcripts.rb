class CreateBuilderSessionTranscripts < ActiveRecord::Migration[8.1]
  def change
    create_table :builder_session_transcripts do |t|
      t.references :builder_session, null: false, foreign_key: true, index: { unique: true }
      t.string :state, null: false, default: "pending"
      t.string :source
      t.text :content
      t.text :google_conference_record_name
      t.text :google_transcript_names
      t.integer :attempts, null: false, default: 0
      t.datetime :last_attempted_at
      t.datetime :next_attempt_at
      t.datetime :imported_at
      t.datetime :deleted_at
      t.string :last_error_code

      t.timestamps
    end

    add_index :builder_session_transcripts, [ :state, :next_attempt_at ]
  end
end
