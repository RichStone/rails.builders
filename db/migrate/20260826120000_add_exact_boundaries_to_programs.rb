class AddExactBoundariesToPrograms < ActiveRecord::Migration[8.1]
  def change
    add_column :programs, :starts_at, :datetime
    add_column :programs, :ends_at, :datetime
    add_column :programs, :schedule_time_zone, :string
  end
end
