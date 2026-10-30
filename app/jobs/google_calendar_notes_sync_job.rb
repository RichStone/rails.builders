class GoogleCalendarNotesSyncJob < ApplicationJob
  queue_as :default

  def perform(builder_session_id = nil)
    records = BuilderSessionTranscript.joins(:builder_session)
      .where(builder_sessions: { state: "completed" }).where.not(state: "deleted")
      .where(calendar_notes_next_attempt_at: ..Time.current)
    records = records.where(builder_session_id:) if builder_session_id
    records.find_each { |record| sync(record) }
  end

  private

  def sync(record)
    session = record.builder_session
    attempted_at = Time.current.floor(6)
    claimed = session.with_lock do
      record.reload
      next false unless session.session_record_writable? && record.calendar_notes_next_attempt_at && record.calendar_notes_next_attempt_at <= attempted_at

      record.update!(calendar_notes_attempted_at: attempted_at, calendar_notes_next_attempt_at: attempted_at + 10.minutes)
      true
    end
    return unless claimed

    connection = session.program.calendar_connection
    if !connection
      finish(record, attempted_at:, error_code: "CalendarConnectionMissing", retryable: false)
    elsif connection.google_calendar_id != session.source_calendar_id
      finish(record, attempted_at:, error_code: "CalendarMismatch", retryable: false)
    elsif !connection.status.in?(%w[connected error])
      finish(record, attempted_at:, error_code: "GoogleAuthorizationRequired", retryable: false)
    else
      notes = client_for(connection).notes_for(session)
      finish(record, attempted_at:, notes:, connection:, error_code: notes.present? ? nil : "NotesNotFound")
    end
  rescue GoogleWorkspace::NotesClient::AuthorizationRequired
    finish(record, attempted_at:, error_code: "GoogleNotesPermissionRequired", retryable: false)
  rescue GoogleWorkspace::CalendarClient::SessionEventMismatch
    finish(record, attempted_at:, error_code: "CalendarMismatch", retryable: false)
  rescue GoogleWorkspace::AuthorizationRequired, Google::Apis::AuthorizationError, Signet::AuthorizationError
    finish(record, attempted_at:, error_code: "GoogleAuthorizationRequired", retryable: false)
  rescue StandardError => error
    finish(record, attempted_at:, error_code: error.class.name.first(100))
  end

  def client_for(connection)
    GoogleWorkspace::NotesClient.new(connection:)
  end

  def finish(record, attempted_at:, notes: nil, error_code: nil, retryable: true, connection: nil)
    session = record.builder_session
    session.with_lock do
      record.reload
      return unless session.session_record_writable? && record.calendar_notes_attempted_at == attempted_at

      if notes.present? && !ProgramCalendarConnection.where(id: connection.id, program_id: session.program_id,
          google_calendar_id: connection.google_calendar_id, status: %w[connected error]).exists?
        notes = nil
        error_code = "CalendarConnectionMissing"
        retryable = false
      end

      deadline = session.ended_at && session.ended_at + 24.hours
      next_attempt = [ Time.current + 15.minutes, deadline ].min if error_code && retryable && deadline && Time.current < deadline
      automatic_at = session.ended_at && session.ended_at + 1.hour
      next_attempt = [ next_attempt, automatic_at ].compact.min if automatic_at && Time.current < automatic_at
      attributes = { calendar_notes_next_attempt_at: next_attempt, calendar_notes_error_code: error_code }
      attributes.merge!(calendar_notes: notes, calendar_notes_synced_at: Time.current) if notes.present?
      record.update!(attributes)
    end
  end
end
