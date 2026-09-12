class AddWeeklySessionRecords < ActiveRecord::Migration[8.1]
  def change
    add_column :builder_session_transcripts, :wispr_meeting_id, :string
    add_index :builder_session_transcripts, :wispr_meeting_id, unique: true

    create_table :next_session_promises do |t|
      t.references :builder_session, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.text :body, null: false
      t.timestamps
    end
    add_index :next_session_promises, [ :builder_session_id, :user_id ], unique: true

    create_table :peer_feedbacks do |t|
      t.references :builder_session, null: false, foreign_key: true
      t.references :author, null: false, foreign_key: { to_table: :users }
      t.references :recipient, null: false, foreign_key: { to_table: :users }
      t.text :body, null: false
      t.string :sentiment, null: false
      t.string :source, null: false
      t.string :source_key, null: false
      t.timestamps
    end
    add_index :peer_feedbacks, [ :builder_session_id, :source_key ], unique: true

    create_table :builder_session_chat_logs do |t|
      t.references :builder_session, null: false, foreign_key: true, index: { unique: true }
      t.text :content, null: false
      t.string :source, null: false
      t.datetime :imported_at, null: false
      t.timestamps
    end
  end
end
