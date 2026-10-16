class GoogleCalendarAttendeeJob < ApplicationJob
  queue_as :default

  def perform(connection_id, user_id, send_notification)
    connection = ProgramCalendarConnection.find_by(id: connection_id)
    user = User.find_by(id: user_id)
    return unless connection && user
    return unless connection.status == "connected" && user.active?
    return if Time.current >= connection.program.countdown_ends_at

    invitation_attempted = true
    client_for(connection).add_attendee_to_upcoming_events(
      calendar_id: connection.google_calendar_id,
      starts_at: Time.current,
      ends_at: connection.program.countdown_ends_at,
      email: user.email,
      send_notification: send_notification && user.receives_enrollment_notifications?
    )
  rescue GoogleWorkspace::AuthorizationRequired, Google::Apis::AuthorizationError, Signet::AuthorizationError => error
    record_failure(connection, "reauthorization_required", error)
    raise
  rescue StandardError => error
    record_failure(connection, "error", error)
    raise
  ensure
    # A partial provider failure may still have added an early event's invitation.
    if invitation_attempted && (current_user = User.find_by(id: user.id)) && !current_user.active?
      current_user.builder_session_attendances.where.not(strike_inactivated_at: nil).update_all(strike_calendar_removed_at: nil)
      StrikeLimitJob.perform_later
    end
  end

  private

  def client_for(connection)
    GoogleWorkspace::CalendarClient.new(connection:)
  end

  def record_failure(connection, status, error)
    connection&.update_columns(
      status:,
      last_error_code: error.class.name.first(100),
      updated_at: Time.current
    )
  rescue ActiveRecord::RecordNotFound
    nil
  end
end
