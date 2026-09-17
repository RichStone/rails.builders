require "test_helper"

class GoogleCalendarAttendeeJobTest < ActiveJob::TestCase
  FakeClient = Struct.new(:calls, :error) do
    def add_attendee_to_upcoming_events(**attributes)
      raise error if error

      calls << attributes
    end
  end

  class StubbedJob < GoogleCalendarAttendeeJob
    attr_accessor :client

    private

    def client_for(_connection)
      client
    end
  end

  setup do
    @facilitator = User.create!(
      email: "facilitator@example.com",
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
      google_account_email: @facilitator.email,
      google_calendar_id: "sessions@group.calendar.google.com",
      google_calendar_name: "Rails.Builders Sessions",
      oauth_token_json: "{}",
      status: "connected"
    )
    @builder = User.create!(
      email: "builder@example.com",
      enrollment_status: "active",
      verified_at: Time.current
    )
  end

  test "adds an active Builder to upcoming Calendar events with the selected notification mode" do
    client = FakeClient.new([], nil)
    job = StubbedJob.new
    job.client = client

    travel_to Time.zone.parse("2026-09-13 12:00") do
      job.perform(@connection.id, @builder.id, false)
    end

    assert_equal [ {
      calendar_id: @connection.google_calendar_id,
      starts_at: Time.zone.parse("2026-09-13 12:00"),
      ends_at: @program.countdown_ends_at,
      email: @builder.email,
      send_notification: false
    } ], client.calls
  end

  test "marks the Calendar connection for reauthorization when its token cannot add attendees" do
    job = StubbedJob.new
    job.client = FakeClient.new([], GoogleWorkspace::AuthorizationRequired.new("secret token detail"))

    assert_raises(GoogleWorkspace::AuthorizationRequired) do
      job.perform(@connection.id, @builder.id, true)
    end

    assert_equal "reauthorization_required", @connection.reload.status
    assert_equal "GoogleWorkspace::AuthorizationRequired", @connection.last_error_code
    assert_not_includes @connection.last_error_code, "secret"
  end

  test "enrollment opt-out suppresses the requested Calendar invitation email" do
    @builder.update!(enrollment_notifications: false)
    client = FakeClient.new([], nil)
    job = StubbedJob.new
    job.client = client

    job.perform(@connection.id, @builder.id, true)

    assert_equal false, client.calls.sole.fetch(:send_notification)
  end

  test "does not invite someone who is no longer an active Builder when the job runs" do
    @builder.update!(enrollment_status: "withdrawn")
    client = FakeClient.new([], nil)
    job = StubbedJob.new
    job.client = client

    job.perform(@connection.id, @builder.id, true)

    assert_empty client.calls
  end
end
