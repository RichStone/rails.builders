class RemoveOgPriorityFromPrograms < ActiveRecord::Migration[8.1]
  def up
    remove_column :programs, :og_priority
  end

  def down
    add_column :programs, :og_priority, :boolean, null: false, default: false
  end
end
