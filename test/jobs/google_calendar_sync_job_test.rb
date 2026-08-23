require "test_helper"

class GoogleCalendarSyncJobTest < ActiveJob::TestCase
  FakeClient = Struct.new(:events, :error) do
    def list_events(calendar_id:, starts_at:, ends_at:)
      raise error if error

      events
    end
  end

  class StubbedJob < GoogleCalendarSyncJob
    attr_accessor :clients, :requested_connection_ids

    private

    def client_for(connection)
      requested_connection_ids << connection.id
      clients.fetch(connection.id)
    end
  end

  setup do
    @facilitator = User.create!(
      email: "facilitator@example.com",
      name: "Facilitator",
      facilitator: true,
      enrollment_status: "active",
      verified_at: Time.current
    )
  end

  test "syncs every eligible Calendar connection and continues after one fails" do
    failing_connection = create_connection("Failing")
    working_connection = create_connection("Working")
    reauthorization_connection = create_connection("Needs authorization", status: "reauthorization_required")
    authorizing_connection = create_connection("Authorization in progress", status: "authorizing")
    event = {
      id: "event-1",
      status: "confirmed",
      title: "Builder clinic",
      starts_at: Time.zone.parse("2026-09-08 18:00"),
      ends_at: Time.zone.parse("2026-09-08 19:00"),
      time_zone: "Europe/Madrid"
    }
    job = StubbedJob.new
    job.clients = {
      failing_connection.id => FakeClient.new([], RuntimeError.new("temporary failure")),
      working_connection.id => FakeClient.new([ event ], nil)
    }
    job.requested_connection_ids = []

    job.perform

    assert_equal "error", failing_connection.reload.status
    assert_equal "RuntimeError", failing_connection.last_error_code
    assert working_connection.reload.last_synced_at
    assert_equal "Builder clinic", working_connection.program.builder_sessions.find_by!(google_event_id: "event-1").title
    assert_equal [ failing_connection.id, working_connection.id ].sort, job.requested_connection_ids.sort
    assert_nil reauthorization_connection.reload.last_synced_at
    assert_nil authorizing_connection.reload.last_synced_at
  end

  test "can sync one connection immediately" do
    connection = create_connection("Immediate")
    job = StubbedJob.new
    job.clients = { connection.id => FakeClient.new([], nil) }
    job.requested_connection_ids = []

    job.perform(connection.id)

    assert connection.reload.last_synced_at
    assert_equal [ connection.id ], job.requested_connection_ids
  end

  private

  def create_connection(name, status: "connected")
    program = Program.create!(
      name: name,
      starts_on: Date.new(2026, 8, 20),
      ends_on: Date.new(2026, 12, 17),
      capacity: 9,
      main_facilitator: @facilitator
    )
    program.create_calendar_connection!(
      facilitator: @facilitator,
      google_account_email: "facilitator@looplabs.cc",
      google_calendar_id: "#{name.parameterize}@group.calendar.google.com",
      google_calendar_name: name,
      oauth_token_json: '{"refresh_token":"secret"}',
      status: status
    )
  end
end
