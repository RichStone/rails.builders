require "test_helper"

class SessionCancellationTest < ActiveSupport::TestCase
  setup do
    @facilitator = User.create!(email: "host@example.com", facilitator: true, verified_at: Time.current)
    @builder = User.create!(email: "builder@example.com", enrollment_status: "active", verified_at: Time.current, session_reminders: false)
    @program = Program.create!(name: "Continuous", starts_on: Date.current, ends_on: 3.months.from_now.to_date, main_facilitator: @facilitator)
    @program.create_calendar_connection!(
      facilitator: @facilitator, google_account_email: @facilitator.email,
      google_calendar_id: "sessions@example.com", google_calendar_name: "Sessions", oauth_token_json: "{}", status: "connected"
    )
    @session = @program.builder_sessions.create!(
      google_event_id: "series_20261022T153000Z", title: "Builders",
      source_calendar_id: "sessions@example.com",
      scheduled_starts_at: 2.days.from_now, scheduled_ends_at: 2.days.from_now + 90.minutes, time_zone: "Europe/Madrid"
    )
  end

  test "cancellation immediately suppresses reminders and snapshots eligible recipients once" do
    User.create!(email: "muted@example.com", enrollment_status: "active", verified_at: Time.current, notifications_enabled: false)
    User.create!(email: "unverified@example.com", enrollment_status: "active")
    User.create!(email: "removed@example.com", enrollment_status: "removed", facilitator: true, verified_at: Time.current)
    User.create!(email: "inactive@example.com", verified_at: Time.current)

    assert request_cancellation
    assert_equal "cancelled", @session.reload.state
    assert_not @builder.session_reminder_due?(@session, at: 1.day.from_now)
    assert_equal [ @facilitator.id, @builder.id ].sort, @session.cancellation_deliveries.pluck(:user_id).sort
    assert_equal "Rich has an appointment.", @session.cancellation_reason
    assert_not_includes @session.read_attribute_before_type_cast(:cancellation_reason), "appointment"
    assert_not_includes @session.read_attribute_before_type_cast(:source_calendar_id), "sessions@example.com"
    assert_not request_cancellation
    assert_equal 2, @session.cancellation_deliveries.count
  end

  test "stale, past, live, or disconnected sessions and empty reasons cannot be cancelled" do
    original_start = @session.scheduled_starts_at.iso8601(6)
    @session.update!(scheduled_starts_at: 3.days.from_now, scheduled_ends_at: 3.days.from_now + 90.minutes)
    assert_raises(ActiveRecord::RecordInvalid) { request_cancellation(expected_scheduled_starts_at: original_start) }
    assert_raises(ActiveRecord::RecordInvalid) { request_cancellation(reason: " ") }
    @program.calendar_connection.update!(status: "reauthorization_required")
    assert_raises(ActiveRecord::RecordInvalid) { request_cancellation }
    @program.calendar_connection.update!(status: "connected")
    @session.update!(state: "connection")
    assert_raises(ActiveRecord::RecordInvalid) { request_cancellation }
    @session.update!(state: "ready", scheduled_starts_at: 1.hour.ago, scheduled_ends_at: 30.minutes.from_now)
    assert_raises(ActiveRecord::RecordInvalid) { request_cancellation }
    assert_nil @session.reload.cancellation_requested_at
    assert_empty @session.cancellation_deliveries
  end

  test "a changed calendar or unknown source cannot redirect cancellation to another calendar" do
    @program.calendar_connection.update!(google_calendar_id: "new-calendar@example.com")

    assert_raises(ActiveRecord::RecordInvalid) { request_cancellation }
    assert_nil @session.reload.cancellation_requested_at
    assert_equal "ready", @session.state
    assert_empty @session.cancellation_deliveries

    @program.calendar_connection.update!(google_calendar_id: "sessions@example.com")
    @session.update!(source_calendar_id: nil)
    assert_raises(ActiveRecord::RecordInvalid) { request_cancellation }
    assert_nil @session.reload.cancellation_requested_at
    assert_empty @session.cancellation_deliveries
  end

  private

  def request_cancellation(**overrides)
    @session.reload
    @session.request_cancellation!(**{
      reason: "Rich has an appointment.", expected_scheduled_starts_at: @session.scheduled_starts_at.iso8601(6)
    }.merge(overrides))
  end
end
