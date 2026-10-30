require "test_helper"

class CalendarNotesAccessStatusTest < ActionDispatch::IntegrationTest
  setup do
    facilitator = User.create!(email: "facilitator@example.com", facilitator: true, verified_at: Time.current)
    @admin = User.create!(email: "admin@example.com", administrator: true, verified_at: Time.current)
    program = Program.create!(name: "Builders", starts_on: Date.new(2026, 9, 1), ends_on: Date.new(2026, 12, 17), main_facilitator: facilitator)
    @connection = program.create_calendar_connection!(facilitator:, google_account_email: facilitator.email,
      google_calendar_id: "sessions-calendar", google_calendar_name: "Sessions", oauth_token_json: "{}", status: "connected")
    @notes_scope = GoogleWorkspace::Authorization::NOTES_SCOPE
    token = @admin.generate_token_for(:email_verification)
    get verify_email_path(token: token)
    post verify_email_path, params: { token: }
  end

  test "the saved grant recognizes array and space-separated Google scope formats without refreshing credentials" do
    with_stubbed_singleton_method(GoogleWorkspace::Authorization, :new, ->(**) { raise "Must not refresh credentials" }) do
      [ [ @notes_scope ], "https://www.googleapis.com/auth/calendar.calendarlist.readonly #{@notes_scope}" ].each do |scopes|
        @connection.oauth_token_json = { scope: scopes }.to_json
        assert @connection.calendar_notes_access_granted?
      end
    end
  end

  test "missing malformed or unsupported token data does not claim notes access" do
    [ "", "invalid json", "null", "[]", "{}", '{"scope":{}}', '{"scope":false}', '{"scope":["https://www.googleapis.com/auth/calendar.events.owned"]}' ].each do |token|
      @connection.oauth_token_json = token
      assert_not @connection.calendar_notes_access_granted?
    end
  end

  test "the admin page confirms a saved notes grant and removes the consent button" do
    @connection.update!(oauth_token_json: { scope: [ @notes_scope ] }.to_json)

    with_stubbed_singleton_method(GoogleWorkspace::Authorization, :new, ->(**) { raise "Must not refresh credentials" }) do
      get admin_root_path
    end

    assert_response :success
    assert_select ".calendar-connection p", text: "Calendar notes access enabled."
    assert_select "form[action='#{authorize_notes_admin_calendar_connection_path}']", count: 0
  end

  test "the admin page retains the consent button without a saved notes grant" do
    @connection.update!(oauth_token_json: { scope: GoogleWorkspace::Authorization::SCOPES }.to_json)

    get admin_root_path

    assert_response :success
    assert_select "form[action='#{authorize_notes_admin_calendar_connection_path}'] button", text: "Allow calendar notes access"
    assert_select ".calendar-connection p", text: "Calendar notes access enabled.", count: 0
  end
end
