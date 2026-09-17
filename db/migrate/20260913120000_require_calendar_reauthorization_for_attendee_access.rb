class RequireCalendarReauthorizationForAttendeeAccess < ActiveRecord::Migration[8.1]
  def up
    execute <<~SQL.squish
      UPDATE program_calendar_connections
      SET status = 'reauthorization_required', updated_at = CURRENT_TIMESTAMP
      WHERE status IN ('connected', 'error')
    SQL
  end
end
