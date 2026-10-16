require "test_helper"

class StrikeLimitJobTest < ActiveJob::TestCase
  include ActionMailer::TestHelper
  self.use_transactional_tests = false

  FakeClient = Struct.new(:calls, :error, :callback, :post_error) do
    def remove_attendee_from_upcoming_events(**attributes)
      raise error if error
      raise "Calendar HTTP calls must not hold the database writer" if ActiveRecord::Base.connection.transaction_open?

      calls << attributes
      callback&.call
      raise post_error if post_error
    end
  end

  class StubbedJob < StrikeLimitJob
    attr_accessor :client

    private

    def client_for(_connection)
      client
    end
  end

  setup do
    @facilitator = User.create!(email: "facilitator@example.com", facilitator: true, verified_at: Time.current)
    @program = Program.create!(name: "Continuous", starts_on: Date.new(2026, 9, 3), ends_on: Date.new(2026, 12, 17), capacity: 1, main_facilitator: @facilitator)
    @connection = @program.create_calendar_connection!(facilitator: @facilitator, google_account_email: @facilitator.email,
      google_calendar_id: "sessions@group.calendar.google.com", google_calendar_name: "Sessions", oauth_token_json: "{}", status: "connected")
    @builder = User.create!(email: "builder@example.com", name: "Casey", verified_at: Time.current, enrollment_status: "active")
    @sessions = 3.times.map do |index|
      starts_at = Time.utc(2026, 9, 3, 16) + index.weeks
      @program.builder_sessions.create!(title: "Session #{index}", google_event_id: "weekly-#{index}", state: "completed",
        scheduled_starts_at: starts_at, scheduled_ends_at: starts_at + 1.hour, time_zone: "Europe/Madrid").tap do |session|
        session.attendances.create!(user: @builder, display_name: @builder.name, role: "builder", status: "absent")
      end
    end
    @client = FakeClient.new([], nil)
  end

  test "the limit releases one seat, emails once, removes Calendar invites and allows rejoining" do
    waiting = User.create!(email: "waiting@example.com", verified_at: Time.current, enrollment_status: "waitlisted", waitlist_joined_at: 1.day.ago, waitlist_rank: 1)

    assert_difference("ActionMailer::Base.deliveries.size", 1) { perform_job }

    assert @builder.reload.inactive?
    assert @builder.waitlist_eligible?
    assert_equal "absent", @builder.slack_desired_state
    assert waiting.reload.offered?
    strike = @sessions.last.attendances.find_by!(user: @builder)
    assert strike.strike_inactivated_at?
    assert strike.strike_email_sent_at?
    assert strike.strike_calendar_removed_at?
    assert_equal 3, strike.strike_absence_limit
    assert_equal [ @builder.email ], ActionMailer::Base.deliveries.last.to
    assert_equal [ @builder.email ], @client.calls.map { |call| call.fetch(:email) }
    assert_no_difference("ActionMailer::Base.deliveries.size") { perform_job }
    assert_equal 1, @client.calls.size
  end

  test "a missed Calendar update retries without sending the email again" do
    @client.error = IOError.new("Calendar unavailable")
    assert_difference("ActionMailer::Base.deliveries.size", 1) { perform_job }
    strike = @sessions.last.attendances.find_by!(user: @builder)
    assert @builder.reload.inactive?
    assert strike.strike_email_sent_at?
    assert_not strike.strike_calendar_removed_at?

    @client.error = nil
    assert_no_difference("ActionMailer::Base.deliveries.size") { perform_job }
    assert strike.reload.strike_calendar_removed_at?
    assert_equal 1, @client.calls.size
  end

  test "pending cleanup continues after requesting to rejoin the waitlist" do
    @client.error = IOError.new("Calendar unavailable")
    perform_job
    @builder.update!(enrollment_status: "waitlisted", waitlist_rank: 1, waitlist_joined_at: Time.current)
    @client.error = nil
    perform_job
    assert_equal 1, @client.calls.size
    assert @sessions.last.attendances.find_by!(user: @builder).strike_calendar_removed_at?
  end

  test "provider delivery runs without a database writer lock" do
    interceptor = Object.new
    interceptor.define_singleton_method(:delivering_email) do |_mail|
      raise "Email HTTP calls must not hold the database writer" if ActiveRecord::Base.connection.transaction_open?
    end
    ActionMailer::Base.register_interceptor(interceptor)
    assert_difference("ActionMailer::Base.deliveries.size", 1) { perform_job }
  ensure
    ActionMailer::Base.unregister_interceptor(interceptor)
  end

  test "overlapping runs cannot send or remove twice while a followup is claimed" do
    @client.callback = -> { perform_job }
    assert_difference("ActionMailer::Base.deliveries.size", 1) { perform_job }
    assert_equal 1, @client.calls.size
  end

  test "an abandoned claim retries after its lease expires" do
    @builder.update!(notifications_enabled: false)
    @client.error = IOError.new("Calendar unavailable")
    perform_job
    strike = @sessions.last.attendances.find_by!(user: @builder)
    strike.update!(strike_followups_claimed_at: Time.current)
    @client.error = nil
    perform_job
    assert_empty @client.calls

    travel_to 11.minutes.from_now do
      perform_job
      assert strike.reload.strike_calendar_removed_at?
      assert_nil strike.strike_followups_claimed_at
    end
  end

  test "reactivation during Calendar removal queues a fresh invitation after the removal" do
    @client.callback = -> { @builder.reload.update!(enrollment_status: "active") }
    assert_enqueued_with(job: GoogleCalendarAttendeeJob, args: [ @connection.id, @builder.id, false ]) { perform_job }
    assert @builder.reload.active?
  end

  test "reactivation during a partially failed removal still restores invitations" do
    @client.callback = -> { @builder.reload.update!(enrollment_status: "active") }
    @client.post_error = IOError.new("Later Calendar event failed")
    assert_enqueued_with(job: GoogleCalendarAttendeeJob, args: [ @connection.id, @builder.id, false ]) { perform_job }
    assert @builder.reload.active?
    assert_not @sessions.last.attendances.find_by!(user: @builder).strike_calendar_removed_at?
  end

  test "email delivery failure retries while Calendar removal still completes" do
    interceptor = Object.new
    interceptor.define_singleton_method(:delivering_email) { |_mail| raise IOError, "Mail unavailable" }
    ActionMailer::Base.register_interceptor(interceptor)
    assert_no_difference("ActionMailer::Base.deliveries.size") { perform_job }
    strike = @sessions.last.attendances.find_by!(user: @builder)
    assert_not strike.strike_email_sent_at?
    assert strike.strike_calendar_removed_at?

    ActionMailer::Base.unregister_interceptor(interceptor)
    assert_difference("ActionMailer::Base.deliveries.size", 1) { perform_job }
    assert strike.reload.strike_email_sent_at?
    assert_equal 1, @client.calls.size
  ensure
    ActionMailer::Base.unregister_interceptor(interceptor)
  end

  test "notification opt-outs do not prevent releasing the seat and send when re-enabled" do
    @builder.update!(notifications_enabled: false)
    assert_no_difference("ActionMailer::Base.deliveries.size") { perform_job }
    assert @builder.reload.inactive?
    assert_equal 1, @client.calls.size

    @builder.update!(notifications_enabled: true)
    assert_difference("ActionMailer::Base.deliveries.size", 1) { perform_job }
  end

  test "a returning Builder starts fresh and stale followups cannot remove their renewed invite" do
    @client.error = IOError.new("Calendar unavailable")
    perform_job
    assert @builder.reload.inactive?
    @builder.update!(enrollment_status: "active")
    @client.error = nil
    assert_no_difference("ActionMailer::Base.deliveries.size") { perform_job }
    assert @builder.reload.active?
    assert_empty @client.calls

    # New misses after reactivation can reach a fresh limit.
    3.times do |index|
      starts_at = Time.current + (index + 1).days
      @program.builder_sessions.create!(title: "Return #{index}", google_event_id: "return-#{index}", state: "completed",
        scheduled_starts_at: starts_at, scheduled_ends_at: starts_at + 1.hour, time_zone: "Europe/Madrid").attendances.create!(
          user: @builder, display_name: @builder.name, role: "builder", status: "absent")
    end
    perform_job
    assert @builder.reload.active?, "Future sessions must not deactivate a Builder"
    travel_to 4.days.from_now do
      assert_difference("ActionMailer::Base.deliveries.size", 1) { perform_job }
      assert @builder.reload.inactive?
    end
  end

  test "configured limits ignore non-completed sessions and a missing or present record breaks the streak" do
    @program.update!(consecutive_absence_limit: 4)
    perform_job
    assert @builder.reload.active?
    @program.update!(consecutive_absence_limit: 3)
    @sessions.last.update!(state: "cancelled")
    perform_job
    assert @builder.reload.active?
    @sessions.last.update!(state: "completed")
    last_record = @sessions.last.attendances.find_by!(user: @builder)
    last_record.update!(status: "present")
    perform_job
    assert @builder.reload.active?
    last_record.destroy!
    perform_job
    assert @builder.reload.active?
  end

  test "facilitators and users who are not active are exempt from automatic release" do
    %w[inactive waitlisted offered withdrawn removed].each do |status|
      @builder.update!(enrollment_status: status, offer_expires_at: (3.days.from_now if status == "offered"))
      perform_job
      assert_equal status, @builder.reload.enrollment_status
    end
    @builder.update_columns(enrollment_status: "active", facilitator: true)
    perform_job
    assert @builder.reload.active?
    assert_empty @client.calls
  end

  private

  def perform_job
    StubbedJob.new.tap { |job| job.client = @client }.perform
  end
end
