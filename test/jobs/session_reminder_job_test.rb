require "test_helper"

class SessionReminderJobTest < ActiveJob::TestCase
  include ActionMailer::TestHelper

  FakeClient = Struct.new(:declined_emails, :calls, :error) do
    def declined_attendee_emails(**attributes)
      calls << attributes
      raise error if error

      declined_emails
    end
  end

  class StubbedJob < SessionReminderJob
    attr_accessor :client

    private

    def client_for(_connection)
      client
    end
  end

  setup do
    @facilitator = User.create!(
      email: "facilitator@example.com", facilitator: true, verified_at: Time.current,
      session_reminders: false
    )
    @user = User.create!(email: "builder@example.com", verified_at: Time.current, enrollment_status: "active")
    @program = Program.create!(
      name: "Continuous", starts_on: Date.new(2026, 9, 3), ends_on: Date.new(2026, 12, 17),
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
    @session = @program.builder_sessions.create!(
      google_event_id: "weekly-session", title: "Weekly Rails.Builders",
      scheduled_starts_at: Time.utc(2026, 9, 17, 15, 30),
      scheduled_ends_at: Time.utc(2026, 9, 17, 17, 0), time_zone: "Europe/Amsterdam"
    )
    @client = FakeClient.new([], [], nil)
  end

  test "the default reminder sends once at 36 hours before the session with its time and links" do
    travel_to Time.utc(2026, 9, 16, 3, 29) do
      assert_no_emails { perform_job }
    end
    travel_to Time.utc(2026, 9, 16, 3, 30) do
      assert_emails(1) { perform_job }
      assert_no_emails { perform_job }
    end

    mail = ActionMailer::Base.deliveries.last
    assert_equal [ @user.email ], mail.to
    [ mail.html_part.body.decoded, mail.text_part.body.decoded ].each do |body|
      assert_includes body, "Weekly Rails.Builders"
      assert_includes body, "Thursday, 17 September at 17:30 CEST"
      assert_includes body, "Europe/Amsterdam"
      assert_includes body, "http://example.com/sessions/#{@session.id}"
      assert_includes body, "Configure your notifications"
      assert_includes body, "http://example.com/notifications"
    end
  end

  test "an Active Builder who declined the Calendar event gets no reminder" do
    @client.declined_emails = [ @user.email ]

    travel_to Time.utc(2026, 9, 16, 3, 30) do
      assert_no_emails { perform_job }
    end

    assert_equal [ {
      calendar_id: @connection.google_calendar_id,
      event_id: @session.google_event_id
    } ], @client.calls
    assert SessionReminder.find_by!(user: @user, builder_session: @session).calendar_declined_at?

    travel_to Time.utc(2026, 9, 16, 3, 31) do
      assert_no_emails { perform_job }
    end
    assert_equal 1, @client.calls.size
  end

  test "a Calendar failure leaves the reminder pending for the next run" do
    @client.error = IOError.new("Calendar unavailable")

    travel_to Time.utc(2026, 9, 16, 3, 30) do
      assert_no_emails { perform_job }
      reminder = SessionReminder.find_by!(user: @user, builder_session: @session)
      assert_not reminder.processed?

      @client.error = nil
      assert_emails(1) { perform_job }
      assert reminder.reload.sent_at?
    end
  end

  test "custom timing uses the latest preference and catches up after a missed tick" do
    travel_to Time.utc(2026, 9, 17, 7, 30) do
      @user.update!(session_reminder_hours: 2)
      assert_no_emails { perform_job }
    end
    travel_to Time.utc(2026, 9, 17, 13, 35) do
      assert_emails(1) { perform_job }
      @user.update!(session_reminder_hours: 36)
      assert_no_emails { perform_job }
    end
  end

  test "opt-outs and ineligible builders get no reminders while verified facilitators do" do
    @user.update!(session_reminders: false)
    User.create!(email: "paused@example.com", enrollment_status: "active", verified_at: Time.current, notifications_enabled: false)
    User.create!(email: "unverified@example.com", enrollment_status: "active")
    User.create!(email: "waitlisted@example.com", enrollment_status: "waitlisted", verified_at: Time.current)
    User.create!(email: "withdrawn@example.com", enrollment_status: "withdrawn", verified_at: Time.current)
    User.create!(email: "removed@example.com", enrollment_status: "removed", facilitator: true, verified_at: Time.current)
    User.create!(email: "reminders-facilitator@example.com", enrollment_status: "inactive", facilitator: true, verified_at: Time.current)

    travel_to Time.utc(2026, 9, 17, 7, 30) do
      assert_emails(1) { perform_job }
    end
    assert_equal [ "reminders-facilitator@example.com" ], ActionMailer::Base.deliveries.last.to
  end

  test "cancelled live and past sessions do not send reminders" do
    travel_to Time.utc(2026, 9, 17, 7, 30) do
      %w[cancelled connection completed].each do |state|
        @session.update_columns(state: state)
        assert_no_emails { perform_job }
      end
    end
    @session.update!(state: "ready")
    travel_to Time.utc(2026, 9, 17, 15, 30) do
      assert_no_emails { perform_job }
    end
  end

  test "rescheduling uses the new start time and permits a reminder for the changed session" do
    travel_to Time.utc(2026, 9, 16, 3, 30) do
      @session.update!(scheduled_starts_at: Time.utc(2026, 9, 17, 16, 30), scheduled_ends_at: Time.utc(2026, 9, 17, 18, 0))
      assert_no_emails { perform_job }
    end
    travel_to Time.utc(2026, 9, 16, 4, 30) do
      assert_emails(1) { perform_job }
      @session.update!(scheduled_starts_at: Time.utc(2026, 9, 24, 15, 30), scheduled_ends_at: Time.utc(2026, 9, 24, 17, 0))
      assert_no_emails { perform_job }
    end
    travel_to Time.utc(2026, 9, 23, 3, 30) do
      assert_emails(1) { perform_job }
      assert_no_emails { perform_job }
    end
  end

  test "failed delivery retries on the next run and does not block other builders" do
    User.create!(email: "another@example.com", verified_at: Time.current, enrollment_status: "active")
    failing_recipient = @user.email
    interceptor = Object.new
    interceptor.define_singleton_method(:delivering_email) do |mail|
      raise IOError, "Mail provider unavailable" if mail.to == [ failing_recipient ]
    end

    travel_to Time.utc(2026, 9, 17, 7, 30) do
      ActionMailer::Base.register_interceptor(interceptor)
      assert_emails(1) { perform_job }
      ActionMailer::Base.unregister_interceptor(interceptor)
      assert_emails(1) { perform_job }
      assert_equal [ @user.email ], ActionMailer::Base.deliveries.last.to
      assert_no_emails { perform_job }
    end
  ensure
    ActionMailer::Base.unregister_interceptor(interceptor)
  end

  private

  def perform_job
    StubbedJob.new.tap { |job| job.client = @client }.perform
  end
end
