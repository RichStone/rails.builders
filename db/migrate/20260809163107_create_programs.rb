class CreatePrograms < ActiveRecord::Migration[8.1]
  def change
    create_table :programs do |t|
      t.string :name, null: false
      t.date :starts_on, null: false
      t.date :ends_on, null: false
      t.integer :capacity, null: false, default: 9
      t.boolean :og_priority, null: false, default: true
      t.boolean :promotions_paused, null: false, default: false

      t.timestamps
    end
  end
end
