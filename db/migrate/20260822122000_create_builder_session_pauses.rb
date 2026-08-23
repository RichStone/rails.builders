class CreateBuilderSessionPauses < ActiveRecord::Migration[8.1]
  def change
    create_table :builder_session_pauses do |t|
      t.references :builder_session, null: false, foreign_key: true
      t.datetime :started_at, null: false
      t.datetime :ended_at

      t.timestamps
    end

    add_index :builder_session_pauses,
      :builder_session_id,
      unique: true,
      where: "ended_at IS NULL",
      name: "index_builder_session_pauses_on_open_pause"
  end
end
