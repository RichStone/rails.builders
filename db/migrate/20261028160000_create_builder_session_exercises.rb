class CreateBuilderSessionExercises < ActiveRecord::Migration[8.1]
  def change
    create_table :builder_session_exercises do |t|
      t.references :builder_session, null: false, foreign_key: true, index: { unique: true }
      t.text :body, null: false
      t.timestamps
    end
  end
end
