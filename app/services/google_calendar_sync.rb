class GoogleCalendarSync
  def initialize(connection:, client:)
    @connection = connection
    @client = client
  end

  def call
    connection.reload
    connection_version = connection.updated_at
    sync_started_at = Time.current
    calendar_id = connection.google_calendar_id
    starts_at, ends_at = calendar_range
    events = client.list_events(
      calendar_id: calendar_id,
      starts_at:,
      ends_at:
    )
    seen_event_ids = []

    BuilderSession.transaction do
      locked_connection = ProgramCalendarConnection.lock.find(connection.id)
      next if stale_sync?(locked_connection, connection_version:, sync_started_at:)

      events.each do |event|
        next if event[:all_day]

        seen_event_ids << event[:id]
        reconcile_event!(event)
      end
      cancel_missing_upcoming_sessions!(seen_event_ids)
      locked_connection.update!(status: "connected", last_synced_at: sync_started_at, last_error_code: nil)
    end
  rescue GoogleWorkspace::AuthorizationRequired, Google::Apis::AuthorizationError, Signet::AuthorizationError => error
    record_connection_failure(
      status: "reauthorization_required",
      error:,
      connection_version:,
      sync_started_at:
    )
    raise
  rescue StandardError => error
    record_connection_failure(status: "error", error:, connection_version:, sync_started_at:)
    raise
  end

  private

  attr_reader :connection, :client

  delegate :program, to: :connection

  def stale_sync?(locked_connection, connection_version:, sync_started_at:)
    locked_connection.updated_at != connection_version ||
      (locked_connection.last_synced_at && locked_connection.last_synced_at >= sync_started_at)
  end

  def record_connection_failure(status:, error:, connection_version:, sync_started_at:)
    return unless connection_version && sync_started_at

    ProgramCalendarConnection.transaction do
      locked_connection = ProgramCalendarConnection.lock.find(connection.id)
      next if stale_sync?(locked_connection, connection_version:, sync_started_at:)

      locked_connection.update_columns(
        status: status,
        last_error_code: error.class.name.first(100),
        updated_at: Time.current
      )
    end
  rescue ActiveRecord::RecordNotFound
    nil
  end

  def reconcile_event!(event)
    session = program.builder_sessions.find_or_initialize_by(google_event_id: event.fetch(:id))
    return unless session.new_record? || session.state.in?(%w[ready cancelled])

    if event[:status] == "cancelled"
      session.update!(state: "cancelled") if session.persisted?
      return
    end

    session.assign_attributes(
      assigned_facilitator: program.main_facilitator,
      title: event[:title].presence || "Rails Builders Session",
      description: event[:description],
      location: event[:location],
      meet_url: GoogleWorkspace::MeetLink.url(event[:meet_url]),
      scheduled_starts_at: event.fetch(:starts_at),
      scheduled_ends_at: event.fetch(:ends_at),
      time_zone: event[:time_zone].presence || connection.google_calendar_time_zone || "UTC",
      state: "ready"
    )
    session.save!
  end

  def cancel_missing_upcoming_sessions!(seen_event_ids)
    scope = program.builder_sessions.where(state: %w[ready cancelled])
    scope = scope.where.not(google_event_id: seen_event_ids) if seen_event_ids.any?
    scope.update_all(state: "cancelled", updated_at: Time.current)
  end

  def calendar_range
    zone = ActiveSupport::TimeZone[connection.google_calendar_time_zone] if connection.google_calendar_time_zone.present?
    zone ||= Time.zone
    [
      zone.parse(program.starts_on.iso8601).beginning_of_day,
      zone.parse((program.ends_on + 1.day).iso8601).beginning_of_day
    ]
  end
end
