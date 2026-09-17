class AddCalendarDeclinedAtToSessionReminders < ActiveRecord::Migration[8.1]
  def change
    add_column :session_reminders, :calendar_declined_at, :datetime
  end
end
