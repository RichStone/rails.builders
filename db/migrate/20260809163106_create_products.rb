class CreateProducts < ActiveRecord::Migration[8.1]
  def change
    create_table :products do |t|
      t.references :user, null: false, foreign_key: true
      t.string :name, null: false
      t.string :url, null: false
      t.boolean :focus, null: false, default: false

      t.timestamps
    end

    add_index :products, :focus
  end
end
