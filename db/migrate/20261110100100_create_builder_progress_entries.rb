class CreateBuilderProgressEntries < ActiveRecord::Migration[8.1]
  def change
    create_table :builder_progress_entries do |t|
      t.references :builder_session, null: false, foreign_key: true, index: false
      t.references :user, null: false, foreign_key: true
      t.text :body, null: false
      t.text :comparison
      t.text :source, null: false
      t.timestamps

      t.index [ :builder_session_id, :user_id ], unique: true
    end
  end
end
