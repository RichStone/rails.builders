class GoogleMeetTranscriptImportJob < ApplicationJob
  queue_as :default

  RETRYABLE_STATES = BuilderSessionTranscript::AUTOMATIC_IMPORT_STATES
  IMPORT_WINDOW = 24.hours

  def perform(transcript_id = nil)
    attempted_at = Time.current
    transcripts = BuilderSessionTranscript.where(state: RETRYABLE_STATES)
    transcripts = if transcript_id
      transcripts.where(id: transcript_id)
    else
      transcripts.where("next_attempt_at IS NULL OR next_attempt_at <= ?", attempted_at)
    end

    transcripts.find_each { |transcript| import(transcript, attempted_at: attempted_at) }
  end

  private

  def import(transcript, attempted_at:)
    builder_session = transcript.builder_session
    deadline = (builder_session.ended_at || transcript.created_at) + IMPORT_WINDOW
    final_attempt = final_attempt_due?(transcript, attempted_at:, deadline:)

    if attempted_at >= deadline && !final_attempt
      mark_unavailable(transcript, error_code: "ImportWindowExpired")
      return
    end

    if builder_session.meet_url.blank?
      mark_unavailable(transcript, error_code: "MeetingLinkMissing")
      return
    end

    connection = builder_session.program.calendar_connection
    unless connection
      record_failure(transcript, attempted_at: attempted_at, deadline: deadline, error_code: "CalendarConnectionMissing")
      return
    end

    if connection.status == "reauthorization_required"
      record_failure(transcript, attempted_at: attempted_at, deadline: deadline, error_code: "GoogleReauthorizationRequired")
      return
    end

    connection_version = connection.updated_at
    GoogleMeetTranscriptImport.new(transcript: transcript, client: client_for(connection)).call
    if final_attempt
      mark_unavailable(transcript, error_code: "ImportWindowExpired")
    else
      cap_next_attempt_at(transcript, deadline: deadline)
    end
  rescue GoogleWorkspace::AuthorizationRequired, Google::Apis::AuthorizationError, Signet::AuthorizationError => error
    mark_connection_for_reauthorization(connection, connection_version:, error:)
    handle_failure(transcript, attempted_at:, deadline:, error_code: error.class.name.first(100))
  rescue StandardError => error
    handle_failure(transcript, attempted_at:, deadline:, error_code: error.class.name.first(100))
  end

  def client_for(connection)
    GoogleWorkspace::MeetClient.new(connection: connection)
  end

  def mark_connection_for_reauthorization(connection, connection_version:, error:)
    return unless connection && connection_version

    connection.with_lock do
      next unless connection.updated_at == connection_version

      connection.update!(
        status: "reauthorization_required",
        last_error_code: error.class.name.first(100)
      )
    end
  rescue ActiveRecord::RecordNotFound
    nil
  end

  def cap_next_attempt_at(transcript, deadline:)
    transcript.with_lock do
      return unless retryable?(transcript)
      return unless transcript.next_attempt_at && transcript.next_attempt_at > deadline

      transcript.update!(next_attempt_at: deadline)
    end
  end

  def record_failure(transcript, attempted_at:, deadline:, error_code:)
    transcript.with_lock do
      return unless retryable?(transcript)

      attempts = transcript.attempts + 1
      retry_at = attempted_at + [ attempts * 5, 60 ].min.minutes
      transcript.update!(
        state: "processing",
        attempts: attempts,
        last_attempted_at: attempted_at,
        next_attempt_at: [ retry_at, deadline ].min,
        last_error_code: error_code
      )
    end
  end

  def handle_failure(transcript, attempted_at:, deadline:, error_code:)
    if attempted_at >= deadline
      mark_unavailable(transcript, error_code: "ImportWindowExpired")
    else
      record_failure(transcript, attempted_at:, deadline:, error_code:)
    end
  end

  def final_attempt_due?(transcript, attempted_at:, deadline:)
    attempted_at >= deadline && transcript.next_attempt_at && transcript.next_attempt_at >= deadline &&
      transcript.last_attempted_at && transcript.last_attempted_at < deadline
  end

  def mark_unavailable(transcript, error_code:)
    transcript.with_lock do
      return unless retryable?(transcript)

      transcript.update!(state: "unavailable", next_attempt_at: nil, last_error_code: error_code)
    end
  end

  def retryable?(transcript) = transcript.state.in?(RETRYABLE_STATES)
end
