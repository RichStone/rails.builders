require "test_helper"

class SessionCancellationJobTest < ActiveJob::TestCase
  include ActionMailer::TestHelper

  FakeClient = Struct.new(:calls, :error) do
    def delete_event(**attributes)
      calls << attributes
      raise error if error
    end
  end

  class StubbedJob < SessionCancellationJob
    attr_accessor :client

    private

    def client_for(_connection) = client
  end

  setup do
    @facilitator = User.create!(email: "host@example.com", facilitator: true, verified_at: Time.current)
    @user = User.create!(email: "builder@example.com", enrollment_status: "active", verified_at: Time.current)
    @program = Program.create!(name: "Continuous", starts_on: Date.current, ends_on: 3.months.from_now.to_date, main_facilitator: @facilitator)
    @connection = @program.create_calendar_connection!(
      facilitator: @facilitator, google_account_email: @facilitator.email,
      google_calendar_id: "sessions@example.com", google_calendar_name: "Sessions", oauth_token_json: "{}", status: "connected"
    )
    @session = @program.builder_sessions.create!(
      google_event_id: "series_20261022T153000Z", source_calendar_id: @connection.google_calendar_id, title: "Builders",
      scheduled_starts_at: 2.days.from_now, scheduled_ends_at: 2.days.from_now + 90.minutes, time_zone: "Europe/Madrid"
    )
    @session.request_cancellation!(reason: "Rich has an appointment.", expected_scheduled_starts_at: @session.scheduled_starts_at.iso8601(6))
    @client = FakeClient.new([], nil)
  end

  test "removes only the selected occurrence before emailing and finishes once" do
    @client.define_singleton_method(:delete_event) do |**attributes|
      raise "Emails sent before calendar removal" unless ActionMailer::Base.deliveries.empty?
      calls << attributes
    end
    ActionMailer::Base.deliveries.clear
    assert_emails(2) { perform_job }
    assert_equal [ { event_id: @session.google_event_id } ], @client.calls
    assert @session.reload.cancellation_calendar_deleted_at?
    assert @session.cancellation_completed_at?
    assert_nil @session.cancellation_claimed_at
    assert_no_emails { perform_job }
    assert_equal 1, @client.calls.size
  end

  test "calendar failure keeps reminders stopped and retries before any mail is sent" do
    @client.error = IOError.new("Calendar unavailable")
    assert_no_emails { perform_job }
    assert_equal "cancelled", @session.reload.state
    assert_nil @session.cancellation_calendar_deleted_at
    assert_nil @session.cancellation_completed_at
    assert_nil @session.cancellation_claimed_at
    @client.error = nil
    assert_emails(2) { perform_job }
    assert @session.reload.cancellation_completed_at?
  end

  test "a changed calendar cannot delete an occurrence on a different calendar" do
    @connection.update!(google_calendar_id: "other@example.com")
    assert_no_emails { perform_job }
    assert_empty @client.calls
    assert_nil @session.reload.cancellation_completed_at
  end

  test "failed recipients retry without repeating accepted emails or calendar deletion" do
    original = UserMailer.method(:session_cancellation)
    fail_user = true
    replacement = ->(user, session) {
      raise IOError, "Mail unavailable" if user == @user && fail_user
      original.call(user, session)
    }
    with_stubbed_singleton_method(UserMailer, :session_cancellation, replacement) do
      assert_emails(1) { perform_job }
      assert_nil @session.reload.cancellation_completed_at
      assert @session.cancellation_deliveries.find_by!(user: @facilitator).sent_at?
      fail_user = false
      assert_emails(1) { perform_job }
    end
    assert_equal 1, @client.calls.size
    assert @session.reload.cancellation_completed_at?
  end

  test "delivery checks latest opt-out and membership without adding new recipients" do
    @user.update!(notifications_enabled: false)
    User.create!(email: "later@example.com", enrollment_status: "active", verified_at: Time.current)
    assert_emails(1) { perform_job }
    assert @session.cancellation_deliveries.find_by!(user: @user).skipped_at?
    assert @session.reload.cancellation_completed_at?
  end

  test "active claims are left alone and abandoned claims recover through the sweep" do
    @session.update!(cancellation_claimed_at: Time.current)
    assert_no_emails { perform_job }
    assert_empty @client.calls
    travel 11.minutes do
      assert_emails(2) { perform_job }
    end
    assert @session.reload.cancellation_completed_at?
  end

  test "a preexisting reminder delivery also refuses a cancelled session" do
    reminder = SessionReminder.create!(user: @user, builder_session: @session, scheduled_starts_at: @session.scheduled_starts_at)
    assert_no_emails { reminder.process!(declined: false) }
    assert_nil reminder.reload.sent_at
  end

  private

  def perform_job
    StubbedJob.new.tap { |job| job.client = @client }.perform
  end
end
