class SetSessionReminderDefaultTo36Hours < ActiveRecord::Migration[8.1]
  def up
    change_column_default :users, :session_reminder_hours, from: 8, to: 36
    execute "UPDATE users SET session_reminder_hours = 36 WHERE session_reminder_hours = 8"
  end

  def down
    change_column_default :users, :session_reminder_hours, from: 36, to: 8
  end
end
