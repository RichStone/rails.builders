class SessionCancellationJob < ApplicationJob
  CalendarChanged = Class.new(StandardError)

  def perform(session_id = nil)
    sessions = BuilderSession.where.not(cancellation_requested_at: nil).where(cancellation_completed_at: nil)
    sessions = sessions.where(id: session_id) if session_id
    sessions.find_each { |session| process_cancellation(session) }
  end

  private

  def process_cancellation(session)
    claim = session.with_lock do
      next if session.cancellation_completed_at? || session.state != "cancelled"
      next if session.cancellation_claimed_at && session.cancellation_claimed_at > 10.minutes.ago

      claimed_at = Time.current
      session.update!(cancellation_claimed_at: claimed_at)
      claimed_at
    end
    return unless claim

    claimed_record = BuilderSession.where(id: session.id, cancellation_claimed_at: claim)
    remove_calendar_event(session)
    session.cancellation_deliveries.where(sent_at: nil, skipped_at: nil).find_each do |delivery|
      delivery.process!
    rescue StandardError => error
      Rails.error.report(error, context: { session_id: session.id, delivery_id: delivery.id })
    end
    if !session.cancellation_deliveries.where(sent_at: nil, skipped_at: nil).exists?
      claimed_record.update_all(cancellation_completed_at: Time.current, updated_at: Time.current)
    end
  rescue StandardError => error
    Rails.error.report(error, context: { session_id: session.id })
  ensure
    claimed_record&.update_all(cancellation_claimed_at: nil)
  end

  def remove_calendar_event(session)
    return if session.cancellation_calendar_deleted_at?

    connection = session.program.calendar_connection
    unless connection&.status.in?(%w[connected error]) && connection.google_calendar_id == session.source_calendar_id
      raise CalendarChanged, "Reconnect the session's original calendar to finish cancellation"
    end

    client_for(connection).delete_event(event_id: session.google_event_id)
    session.update!(cancellation_calendar_deleted_at: Time.current)
  rescue GoogleWorkspace::AuthorizationRequired, Google::Apis::AuthorizationError, Signet::AuthorizationError => error
    connection.update!(status: "reauthorization_required", last_error_code: error.class.name.first(100))
    raise
  end

  def client_for(connection)
    GoogleWorkspace::CalendarClient.new(connection:)
  end
end
