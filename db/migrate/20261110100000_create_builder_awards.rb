class CreateBuilderAwards < ActiveRecord::Migration[8.1]
  def change
    create_table :builder_awards do |t|
      t.references :builder_session, null: false, foreign_key: true, index: false
      t.references :user, null: false, foreign_key: true
      t.references :baseline_session, foreign_key: { to_table: :builder_sessions, on_delete: :nullify }
      t.references :evidence_session, foreign_key: { to_table: :builder_sessions, on_delete: :nullify }
      t.string :title, null: false
      t.text :citation, null: false
      t.datetime :revealed_at
      t.timestamps

      t.index [ :builder_session_id, :user_id, :title ], unique: true
    end
  end
end
