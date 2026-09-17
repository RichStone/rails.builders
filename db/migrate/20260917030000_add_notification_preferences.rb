class AddNotificationPreferences < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :notifications_enabled, :boolean, default: true, null: false
    add_column :users, :enrollment_notifications, :boolean, default: true, null: false
    add_column :users, :session_reminders, :boolean, default: true, null: false
    add_column :users, :product_update_notifications, :boolean, default: true, null: false
    add_column :users, :session_reminder_hours, :integer, default: 8, null: false
  end
end
