require "test_helper"

class AdminCalendarConnectionsTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  class FakeAuthorization
    attr_reader :revoked

    def initialize(token_store: nil, error: nil, notes_granted: true)
      @token_store = token_store
      @error = error
      @notes_granted = notes_granted
    end

    def authorization_url(request:, redirect_to:, login_hint:)
      raise unless request && redirect_to == "/admin/calendar_connection" && login_hint == "otto@looplabs.cc"

      "https://accounts.google.com/o/oauth2/auth?state=signed"
    end

    def authorize!(request)
      raise @error if @error
      raise unless request.params["code"] == "authorization-code"

      @token_store&.store("connection", '{"refresh_token":"new-notes-grant"}')
      true
    end

    def credentials = Object.new
    def notes_credentials
      Object.new if @notes_granted
    end
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
          name: "Rails.Builders Sessions",
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
          assert_select "option[value='otto-builder-sessions@group.calendar.google.com']", text: "Rails.Builders Sessions"

          assert_enqueued_with(job: GoogleCalendarSyncJob, args: [ connection.id ]) do
            patch admin_calendar_connection_path, params: { calendar_id: "otto-builder-sessions@group.calendar.google.com" }
          end
        end

        assert_redirected_to admin_root_path
        assert_equal "connected", connection.reload.status
        assert_equal "Rails.Builders Sessions", connection.google_calendar_name
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

  test "notes authorization preserves the calendar while a transcript is processing" do
    connection = connected_calendar
    original_token = connection.oauth_token_json
    builder_session = @program.builder_sessions.create!(google_event_id: "completed-event", title: "Completed session",
      scheduled_starts_at: 2.hours.ago, scheduled_ends_at: 1.hour.ago, ended_at: 1.hour.ago,
      time_zone: "Europe/Madrid", state: "completed")
    transcript = builder_session.create_transcript!(state: "processing")

    with_stubbed_singleton_method(GoogleWorkspace::Authorization, :new, ->(token_store: nil, **) { FakeAuthorization.new(token_store:) }) do
      post authorize_notes_admin_calendar_connection_path
      assert_redirected_to %r{\Ahttps://accounts\.google\.com/}
      assert_equal original_token, connection.reload.oauth_token_json
      assert_equal "connected", connection.status

      client = FakeCalendarClient.new
      client.define_singleton_method(:account_email) do
        raise "Token changed before identity verification" unless connection.reload.oauth_token_json == original_token

        "otto@looplabs.cc"
      end
      with_stubbed_singleton_method(GoogleWorkspace::CalendarClient, :new, ->(**) { client }) do
        get callback_admin_calendar_connection_path, params: { code: "authorization-code", state: "signed" }
      end
    end

    assert_redirected_to admin_root_path
    assert_includes connection.reload.oauth_token_json, "new-notes-grant"
    assert_equal "sessions-calendar", connection.google_calendar_id
    assert_equal "connected", connection.status
    assert_equal "processing", transcript.reload.state
  end

  test "denied notes permission leaves the existing calendar credentials usable" do
    connection = connected_calendar
    original = connection.attributes
    authorization = FakeAuthorization.new(error: RuntimeError.new("denied"))

    with_stubbed_singleton_method(GoogleWorkspace::Authorization, :new, ->(**) { authorization }) do
      post authorize_notes_admin_calendar_connection_path
      get callback_admin_calendar_connection_path, params: { error: "access_denied", state: "signed" }
    end

    assert_redirected_to admin_root_path
    assert_equal original, connection.reload.attributes
    assert_nil authorization.revoked
  end

  test "notes authorization rejects a different account without erasing the existing token" do
    connection = connected_calendar
    original = connection.attributes

    with_stubbed_singleton_method(GoogleWorkspace::Authorization, :new, ->(token_store: nil, **) { FakeAuthorization.new(token_store:) }) do
      post authorize_notes_admin_calendar_connection_path
      with_stubbed_singleton_method(GoogleWorkspace::CalendarClient, :new, ->(**) { FakeCalendarClient.new(account_email: "somebody@example.com") }) do
        get callback_admin_calendar_connection_path, params: { code: "authorization-code", state: "signed" }
      end
    end

    assert_redirected_to admin_root_path
    assert_equal original, connection.reload.attributes
    assert_equal "Connect the main facilitator’s Google account.", flash[:alert]
  end

  test "partial notes consent does not replace the original grant" do
    connection = connected_calendar
    original = connection.attributes

    with_stubbed_singleton_method(GoogleWorkspace::Authorization, :new, ->(token_store: nil, **) { FakeAuthorization.new(token_store:, notes_granted: false) }) do
      post authorize_notes_admin_calendar_connection_path
      get callback_admin_calendar_connection_path, params: { code: "authorization-code", state: "signed" }
    end

    assert_redirected_to admin_root_path
    assert_equal original, connection.reload.attributes
  end

  test "notes authorization does not overwrite a concurrent credential refresh" do
    connection = connected_calendar
    client = FakeCalendarClient.new
    client.define_singleton_method(:account_email) do
      connection.update_columns(oauth_token_json: '{"refresh_token":"concurrent-refresh"}')
      "otto@looplabs.cc"
    end

    with_stubbed_singleton_method(GoogleWorkspace::Authorization, :new, ->(token_store: nil, **) { FakeAuthorization.new(token_store:) }) do
      post authorize_notes_admin_calendar_connection_path
      with_stubbed_singleton_method(GoogleWorkspace::CalendarClient, :new, ->(**) { client }) do
        get callback_admin_calendar_connection_path, params: { code: "authorization-code", state: "signed" }
      end
    end

    assert_redirected_to admin_root_path
    assert_includes connection.reload.oauth_token_json, "concurrent-refresh"
    assert_equal "connected", connection.status
  end

  test "notes consent is restricted to Administrators" do
    connection = connected_calendar
    original = connection.attributes
    delete sign_out_path
    sign_in_as(@facilitator)

    post authorize_notes_admin_calendar_connection_path

    assert_redirected_to dashboard_path
    assert_equal original, connection.reload.attributes
  end

  test "stale notes access sends confirmation then resumes the same calendar authorization" do
    connection = connected_calendar
    original = connection.attributes
    travel 16.minutes

    with_stubbed_singleton_method(GoogleWorkspace::Authorization, :new, ->(**) { flunk "Google must wait for email confirmation" }) do
      post authorize_notes_admin_calendar_connection_path
      assert_redirected_to reauthentication_path
      perform_enqueued_jobs { follow_redirect! }
    end
    assert_select "button", text: "Resend confirmation email"
    token = confirmation_token
    get edit_reauthentication_path(token: token)
    assert_response :success
    assert_select "form[data-turbo='false'] button", text: "Confirm identity"
    patch reauthentication_path, params: { token: token, return_to: "https://example.com/untrusted" }
    assert_redirected_to authorize_notes_admin_calendar_connection_path
    assert_equal original, connection.reload.attributes

    with_stubbed_singleton_method(GoogleWorkspace::Authorization, :new, ->(token_store: nil, **) { FakeAuthorization.new(token_store:) }) do
      follow_redirect!
      assert_redirected_to %r{\Ahttps://accounts\.google\.com/}
      with_stubbed_singleton_method(GoogleWorkspace::CalendarClient, :new, ->(**) { FakeCalendarClient.new }) do
        get callback_admin_calendar_connection_path, params: { code: "authorization-code", state: "signed" }
      end
    end
    assert_redirected_to admin_root_path
    assert_includes connection.reload.oauth_token_json, "new-notes-grant"
    get authorize_notes_admin_calendar_connection_path
    assert_redirected_to admin_root_path
  end

  test "calendar writes always require recent authentication" do
    connection = connected_calendar
    original = connection.attributes
    travel 16.minutes

    with_stubbed_singleton_method(GoogleWorkspace::Authorization, :new, ->(**) { flunk "Stale login must not change Google credentials" }) do
      post admin_calendar_connection_path
      assert_redirected_to reauthentication_path
      patch admin_calendar_connection_path, params: { calendar_id: "new" }
      assert_redirected_to reauthentication_path
      post sync_admin_calendar_connection_path
      assert_redirected_to reauthentication_path
      delete admin_calendar_connection_path
      assert_redirected_to reauthentication_path
    end
    assert_equal original, connection.reload.attributes
  end

  test "notes authorization cannot start from a direct GET or an expired continuation" do
    connected_calendar
    with_stubbed_singleton_method(GoogleWorkspace::Authorization, :new, ->(**) { flunk "No authorized continuation" }) do
      get authorize_notes_admin_calendar_connection_path
      assert_redirected_to admin_root_path
      head authorize_notes_admin_calendar_connection_path
      assert_redirected_to admin_root_path
      travel 16.minutes
      post authorize_notes_admin_calendar_connection_path
      perform_enqueued_jobs { follow_redirect! }
      travel 14.minutes
      patch reauthentication_path, params: { token: confirmation_token }
      assert_redirected_to authorize_notes_admin_calendar_connection_path
      travel 2.minutes
      get authorize_notes_admin_calendar_connection_path
      assert_redirected_to admin_root_path
    end
  end

  test "a changed calendar or another sensitive action cannot reuse notes intent" do
    connection = connected_calendar
    travel 16.minutes
    post authorize_notes_admin_calendar_connection_path
    perform_enqueued_jobs { follow_redirect! }
    patch reauthentication_path, params: { token: confirmation_token }
    connection.destroy!
    connected_calendar
    get authorize_notes_admin_calendar_connection_path
    assert_redirected_to admin_root_path

    travel 16.minutes
    post authorize_notes_admin_calendar_connection_path
    perform_enqueued_jobs { follow_redirect! }
    delete admin_calendar_connection_path
    patch reauthentication_path, params: { token: confirmation_token }
    assert_redirected_to admin_root_path
    assert @program.reload.calendar_connection
  end

  test "email confirmation restarts an expired notes callback with fresh OAuth state" do
    connection = connected_calendar
    original = connection.attributes
    verifiers = []
    authorization = ->(code_verifier: nil, **) do
      verifiers << code_verifier
      FakeAuthorization.new
    end
    with_stubbed_singleton_method(GoogleWorkspace::Authorization, :new, authorization) do
      post authorize_notes_admin_calendar_connection_path
      travel 16.minutes
      get callback_admin_calendar_connection_path, params: { code: "expired-authorization-code", state: "old-state" }
      assert_redirected_to reauthentication_path
      perform_enqueued_jobs { follow_redirect! }
      patch reauthentication_path, params: { token: confirmation_token }
      assert_redirected_to authorize_notes_admin_calendar_connection_path
      follow_redirect!
      assert_redirected_to %r{\Ahttps://accounts\.google\.com/}
    end
    assert_equal 2, verifiers.size
    assert_not_equal verifiers.first, verifiers.last
    assert_equal original, connection.reload.attributes
  end

  private

  def confirmation_token
    mail = ActionMailer::Base.deliveries.last
    assert_equal "Confirm your Rails.Builders identity", mail.subject
    url = URI.extract(mail.text_part.body.decoded).find { |value| value.include?("/reauthentication/edit") }
    Rack::Utils.parse_query(URI(url).query).fetch("token")
  end

  def connected_calendar
    @program.create_calendar_connection!(facilitator: @facilitator, google_account_email: @facilitator.email,
      google_calendar_id: "sessions-calendar", google_calendar_name: "Sessions",
      oauth_token_json: '{"refresh_token":"keep-me"}', status: "connected")
  end

  def sign_in_as(user)
    token = user.reload.generate_token_for(:email_verification)
    get verify_email_path(token: token)
    post verify_email_path, params: { token: token }
  end
end
