require "test_helper"

class AdminCalendarConnectionsTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  class FakeAuthorization
    attr_reader :revoked

    def authorization_url(request:, redirect_to:, login_hint:)
      raise unless request && redirect_to == "/admin/calendar_connection" && login_hint == "otto@looplabs.cc"

      "https://accounts.google.com/o/oauth2/auth?state=signed"
    end

    def authorize!(request)
      raise unless request.params["code"] == "authorization-code"

      true
    end

    def credentials = Object.new
    def revoke! = @revoked = true
  end

  class FakeCalendarClient
    def initialize(account_email: "otto@looplabs.cc")
      @account_email = account_email
    end

    def account_email = @account_email

    def owned_secondary_calendars
      [
        {
          id: "otto-builder-sessions@group.calendar.google.com",
          name: "Rails Builders Sessions",
          time_zone: "Europe/Madrid",
          data_owner: "otto@looplabs.cc"
        }
      ]
    end
  end

  setup do
    @facilitator = User.create!(
      email: "otto@looplabs.cc",
      name: "Otto",
      facilitator: true,
      enrollment_status: "active",
      verified_at: Time.current
    )
    @admin = User.create!(email: "admin@example.com", administrator: true, verified_at: Time.current)
    @program = Program.create!(
      name: "Continuous",
      starts_on: Date.new(2026, 8, 20),
      ends_on: Date.new(2026, 12, 17),
      capacity: 9,
      main_facilitator: @facilitator
    )
    sign_in_as(@admin)
  end

  test "Administrator connects the main facilitator and selects an owned secondary calendar" do
    authorization = FakeAuthorization.new
    calendar_client = FakeCalendarClient.new

    with_stubbed_singleton_method(GoogleWorkspace::Authorization, :generate_code_verifier, "secure-code-verifier") do
      with_stubbed_singleton_method(GoogleWorkspace::Authorization, :new, ->(**) { authorization }) do
        post admin_calendar_connection_path
        assert_redirected_to %r{\Ahttps://accounts\.google\.com/}
        assert_equal "[FILTERED]", response.filtered_location

        connection = @program.reload.calendar_connection
        assert_equal "authorizing", connection.status
        assert_equal @facilitator, connection.facilitator

        with_stubbed_singleton_method(GoogleWorkspace::CalendarClient, :new, ->(**) { calendar_client }) do
          get callback_admin_calendar_connection_path, params: { code: "authorization-code", state: "signed" }
          assert_redirected_to admin_calendar_connection_path
          assert_equal "otto@looplabs.cc", connection.reload.google_account_email

          get admin_calendar_connection_path
          assert_response :success
          assert_equal "no-store", response.headers["Cache-Control"]
          assert_select "option[value='otto-builder-sessions@group.calendar.google.com']", text: "Rails Builders Sessions"

          assert_enqueued_with(job: GoogleCalendarSyncJob, args: [ connection.id ]) do
            patch admin_calendar_connection_path, params: { calendar_id: "otto-builder-sessions@group.calendar.google.com" }
          end
        end

        assert_redirected_to admin_root_path
        assert_equal "connected", connection.reload.status
        assert_equal "Rails Builders Sessions", connection.google_calendar_name
        assert_equal "Europe/Madrid", connection.google_calendar_time_zone
      end
    end
  end

  test "OAuth rejects a Google account other than the main facilitator" do
    authorization = FakeAuthorization.new

    with_stubbed_singleton_method(GoogleWorkspace::Authorization, :generate_code_verifier, "secure-code-verifier") do
      with_stubbed_singleton_method(GoogleWorkspace::Authorization, :new, ->(**) { authorization }) do
        post admin_calendar_connection_path
        connection = @program.reload.calendar_connection

        with_stubbed_singleton_method(GoogleWorkspace::CalendarClient, :new, ->(**) { FakeCalendarClient.new(account_email: "somebody@example.com") }) do
          get callback_admin_calendar_connection_path, params: { code: "authorization-code", state: "signed" }
        end

        assert_redirected_to admin_root_path
        assert authorization.revoked
        assert_equal "reauthorization_required", connection.reload.status
        assert_equal "account_mismatch", connection.last_error_code
      end
    end
  end

  test "non-Administrators cannot configure the shared calendar" do
    delete sign_out_path
    sign_in_as(@facilitator)

    get admin_calendar_connection_path

    assert_redirected_to dashboard_path
  end

  test "Calendar credentials cannot be replaced or disconnected during a live session" do
    connection = @program.create_calendar_connection!(
      facilitator: @facilitator,
      google_account_email: @facilitator.email,
      google_calendar_id: "sessions-calendar",
      google_calendar_name: "Sessions",
      oauth_token_json: '{"refresh_token":"keep-me"}',
      status: "connected"
    )
    builder_session = @program.builder_sessions.create!(
      assigned_facilitator: @facilitator,
      google_event_id: "live-event",
      title: "Live session",
      meet_url: "https://meet.google.com/abc-defg-hij",
      scheduled_starts_at: Time.current,
      scheduled_ends_at: 1.hour.from_now,
      time_zone: "Europe/Madrid"
    )
    builder_session.start!(facilitator: @facilitator)

    with_stubbed_singleton_method(GoogleWorkspace::Authorization, :new, ->(**) { FakeAuthorization.new }) do
      post admin_calendar_connection_path
      assert_redirected_to admin_root_path
      assert_equal "connected", connection.reload.status
      assert_includes connection.oauth_token_json, "keep-me"

      delete admin_calendar_connection_path
      assert_redirected_to admin_root_path
      assert ProgramCalendarConnection.exists?(connection.id)
    end
  end

  private

  def sign_in_as(user)
    token = user.reload.generate_token_for(:email_verification)
    get verify_email_path(token: token)
    post verify_email_path, params: { token: token }
  end
end
