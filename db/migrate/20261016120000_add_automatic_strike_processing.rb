class AddAutomaticStrikeProcessing < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :attendance_streak_reset_at, :datetime
    add_column :builder_session_attendances, :strike_inactivated_at, :datetime
    add_column :builder_session_attendances, :strike_absence_limit, :integer
    add_column :builder_session_attendances, :strike_calendar_removed_at, :datetime
    add_column :builder_session_attendances, :strike_followups_claimed_at, :datetime
  end
end
