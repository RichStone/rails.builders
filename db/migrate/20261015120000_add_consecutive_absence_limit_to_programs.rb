class AddConsecutiveAbsenceLimitToPrograms < ActiveRecord::Migration[8.1]
  def change
    add_column :programs, :consecutive_absence_limit, :integer, default: 3, null: false
  end
end
