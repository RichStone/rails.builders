require "test_helper"

class GoogleCalendarSyncTest < ActiveSupport::TestCase
  FakeClient = Struct.new(:events) do
    def list_events(calendar_id:, starts_at:, ends_at:)
      events
    end
  end

  setup do
    @facilitator = User.create!(
      email: "facilitator@example.com",
      name: "Main Facilitator",
      facilitator: true,
      enrollment_status: "active",
      verified_at: Time.current
    )
    @program = Program.create!(
      name: "Continuous",
      starts_on: Date.new(2026, 8, 20),
      ends_on: Date.new(2026, 12, 17),
      capacity: 9,
      main_facilitator: @facilitator
    )
    @connection = @program.create_calendar_connection!(
      facilitator: @facilitator,
      google_account_email: "facilitator@looplabs.cc",
      google_calendar_id: "continuous@group.calendar.google.com",
      google_calendar_name: "Rails Builders — Continuous",
      oauth_token_json: '{"refresh_token":"refresh-secret"}',
      status: "connected"
    )
    assert_not_includes @connection.read_attribute_before_type_cast(:oauth_token_json), "refresh-secret"
  end

  test "reconciles timed Calendar events and cancels missing upcoming sessions" do
    existing = @program.builder_sessions.create!(
      assigned_facilitator: @facilitator,
      google_event_id: "removed-event",
      title: "Old session",
      scheduled_starts_at: Time.zone.parse("2026-09-01 18:00"),
      scheduled_ends_at: Time.zone.parse("2026-09-01 19:00"),
      time_zone: "Europe/Madrid"
    )
    client = FakeClient.new([
      {
        id: "event-1",
        status: "confirmed",
        title: "Builder Clinic",
        description: "Bring the blocker you cannot shake.",
        location: "Online",
        meet_url: "https://meet.google.com/abc-defg-hij",
        starts_at: Time.zone.parse("2026-09-08 18:00"),
        ends_at: Time.zone.parse("2026-09-08 19:00"),
        time_zone: "Europe/Madrid"
      },
      { id: "all-day", status: "confirmed", all_day: true }
    ])

    GoogleCalendarSync.new(connection: @connection, client: client).call

    synced = @program.builder_sessions.find_by!(google_event_id: "event-1")
    assert_equal "Builder Clinic", synced.title
    assert_equal "https://meet.google.com/abc-defg-hij", synced.meet_url
    assert_not_includes synced.read_attribute_before_type_cast(:meet_url), "abc-defg-hij"
    assert_equal @facilitator, synced.assigned_facilitator
    assert_equal "cancelled", existing.reload.state
    assert_nil @program.builder_sessions.find_by(google_event_id: "all-day")
    assert_equal "connected", @connection.reload.status
    assert_in_delta Time.current, @connection.last_synced_at, 1.second
  end

  test "reconciles events when Google refreshes stored credentials during the request" do
    connection = @connection
    event = event_hash(id: "event-1", title: "Builder Clinic")
    client = Object.new
    client.define_singleton_method(:list_events) do |**|
      GoogleWorkspace::TokenStore.new(connection: connection).store(
        "program-calendar-connection:#{connection.id}",
        '{"access_token":"refreshed-access-token","refresh_token":"refresh-secret"}'
      )
      [ event ]
    end

    GoogleCalendarSync.new(connection: @connection, client: client).call

    assert_equal "Builder Clinic", @program.builder_sessions.find_by!(google_event_id: "event-1").title
    assert_includes @connection.reload.oauth_token_json, "refreshed-access-token"
    assert @connection.last_synced_at
  end

  test "updates upcoming sessions without rewriting sessions that already started" do
    upcoming = @program.builder_sessions.create!(
      assigned_facilitator: @facilitator,
      google_event_id: "event-1",
      title: "Before",
      scheduled_starts_at: Time.zone.parse("2026-09-08 18:00"),
      scheduled_ends_at: Time.zone.parse("2026-09-08 19:00"),
      time_zone: "Europe/Madrid"
    )
    started = @program.builder_sessions.create!(
      assigned_facilitator: @facilitator,
      google_event_id: "event-2",
      title: "Started snapshot",
      scheduled_starts_at: Time.zone.parse("2026-09-15 18:00"),
      scheduled_ends_at: Time.zone.parse("2026-09-15 19:00"),
      time_zone: "Europe/Madrid"
    )
    started.start!(facilitator: @facilitator)
    client = FakeClient.new([
      event_hash(id: "event-1", title: "After"),
      event_hash(id: "event-2", title: "Calendar changed")
    ])

    GoogleCalendarSync.new(connection: @connection, client: client).call

    assert_equal "After", upcoming.reload.title
    assert_equal "Started snapshot", started.reload.title
  end

  test "cancels an upcoming session when its Calendar event becomes all-day" do
    session = @program.builder_sessions.create!(
      assigned_facilitator: @facilitator,
      google_event_id: "event-1",
      title: "Previously timed",
      scheduled_starts_at: Time.zone.parse("2026-09-08 18:00"),
      scheduled_ends_at: Time.zone.parse("2026-09-08 19:00"),
      time_zone: "Europe/Madrid"
    )

    GoogleCalendarSync.new(
      connection: @connection,
      client: FakeClient.new([ { id: "event-1", status: "confirmed", all_day: true } ])
    ).call

    assert_equal "cancelled", session.reload.state
  end

  test "marks the connection for reauthorization when stored credentials no longer work" do
    client = Object.new
    client.define_singleton_method(:list_events) do |**|
      raise GoogleWorkspace::AuthorizationRequired, "expired token response"
    end

    assert_raises(GoogleWorkspace::AuthorizationRequired) do
      GoogleCalendarSync.new(connection: @connection, client: client).call
    end

    assert_equal "reauthorization_required", @connection.reload.status
    assert_equal "GoogleWorkspace::AuthorizationRequired", @connection.last_error_code
  end

  test "queries the Program date boundaries in the connected calendar time zone" do
    @connection.update!(google_calendar_time_zone: "Pacific/Auckland")
    client = Class.new do
      attr_reader :starts_at, :ends_at

      def list_events(calendar_id:, starts_at:, ends_at:)
        @starts_at = starts_at
        @ends_at = ends_at
        []
      end
    end.new

    GoogleCalendarSync.new(connection: @connection, client: client).call

    zone = ActiveSupport::TimeZone["Pacific/Auckland"]
    assert_equal zone.parse("2026-08-20").beginning_of_day, client.starts_at
    assert_equal zone.parse("2026-12-18").beginning_of_day, client.ends_at
  end

  test "cancels ready sessions left outside shortened Program dates" do
    outside_program = @program.builder_sessions.create!(
      assigned_facilitator: @facilitator,
      google_event_id: "formerly-in-range",
      title: "No longer in this Program",
      scheduled_starts_at: Time.zone.parse("2026-12-20 18:00"),
      scheduled_ends_at: Time.zone.parse("2026-12-20 19:00"),
      time_zone: "Europe/Madrid"
    )

    GoogleCalendarSync.new(connection: @connection, client: FakeClient.new([])).call

    assert_equal "cancelled", outside_program.reload.state
  end

  test "an older overlapping sync cannot overwrite a newer Calendar snapshot" do
    newer_event = event_hash(id: "event-1", title: "Newest title")
    stale_event = event_hash(id: "event-1", title: "Stale title")
    connection = @connection
    outer_client = Object.new
    outer_client.define_singleton_method(:list_events) do |**|
      GoogleCalendarSync.new(connection: connection, client: FakeClient.new([ newer_event ])).call
      [ stale_event ]
    end

    GoogleCalendarSync.new(connection: @connection, client: outer_client).call

    assert_equal "Newest title", @program.builder_sessions.find_by!(google_event_id: "event-1").title
    assert_equal "connected", @connection.reload.status
  end

  test "an older overlapping failure cannot mark a newer successful sync as errored" do
    newer_event = event_hash(id: "event-1", title: "Newest title")
    connection = @connection
    outer_client = Object.new
    outer_client.define_singleton_method(:list_events) do |**|
      GoogleCalendarSync.new(connection: connection, client: FakeClient.new([ newer_event ])).call
      raise RuntimeError, "stale request failed"
    end

    assert_raises(RuntimeError) { GoogleCalendarSync.new(connection: @connection, client: outer_client).call }

    assert_equal "connected", @connection.reload.status
    assert_nil @connection.last_error_code
  end

  private

  def event_hash(id:, title:)
    {
      id: id,
      status: "confirmed",
      title: title,
      starts_at: Time.zone.parse("2026-09-08 18:00"),
      ends_at: Time.zone.parse("2026-09-08 19:00"),
      time_zone: "Europe/Madrid"
    }
  end
end
