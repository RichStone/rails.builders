class AddStrikeEmailSentAtToBuilderSessionAttendances < ActiveRecord::Migration[8.1]
  def change
    add_column :builder_session_attendances, :strike_email_sent_at, :datetime
  end
end
