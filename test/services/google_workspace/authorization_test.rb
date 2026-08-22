require "test_helper"
require "uri"

class GoogleWorkspace::AuthorizationTest < ActiveSupport::TestCase
  Request = Struct.new(:session, :url)

  setup do
    facilitator = User.create!(
      email: "otto@looplabs.cc",
      name: "Otto",
      facilitator: true,
      enrollment_status: "active",
      verified_at: Time.current
    )
    program = Program.create!(
      name: "Continuous",
      starts_on: Date.new(2026, 8, 20),
      ends_on: Date.new(2026, 12, 17),
      capacity: 9,
      main_facilitator: facilitator
    )
    @connection = program.create_calendar_connection!(
      facilitator: facilitator,
      google_account_email: facilitator.email,
      google_calendar_id: "pending",
      google_calendar_name: "Pending authorization",
      oauth_token_json: "{}",
      status: "authorizing"
    )
    @client_id = Google::Auth::ClientId.new("client-id", "client-secret")
  end

  test "builds a state-protected offline authorization request with PKCE and least scopes" do
    verifier = GoogleWorkspace::Authorization.generate_code_verifier
    request = Request.new({}, "https://builders.test/admin/calendar_connection")
    authorization = GoogleWorkspace::Authorization.new(
      connection: @connection,
      callback_uri: "https://builders.test/admin/calendar_connection/callback",
      code_verifier: verifier,
      client_id: @client_id
    )

    url = authorization.authorization_url(
      request: request,
      redirect_to: "/admin/calendar_connection",
      login_hint: "otto@looplabs.cc"
    )
    params = URI.decode_www_form(URI(url).query).to_h

    assert_includes 43..128, verifier.length
    assert_equal "offline", params.fetch("access_type")
    assert_equal "force", params.fetch("approval_prompt")
    assert_equal "S256", params.fetch("code_challenge_method")
    assert_equal "otto@looplabs.cc", params.fetch("login_hint")
    assert_equal GoogleWorkspace::Authorization::SCOPES.sort, params.fetch("scope").split.sort
    assert request.session.key?(Google::Auth::WebUserAuthorizer::XSRF_KEY)
  end

  test "loads stored credentials from the connection-backed token store" do
    @connection.update!(oauth_token_json: {
      client_id: "client-id",
      access_token: "access-secret",
      refresh_token: "refresh-secret",
      scope: GoogleWorkspace::Authorization::SCOPES,
      expiration_time_millis: 1.hour.from_now.to_i * 1000
    }.to_json)

    credentials = GoogleWorkspace::Authorization.new(
      connection: @connection,
      client_id: @client_id
    ).credentials

    assert_equal "access-secret", credentials.access_token
    assert_equal "refresh-secret", credentials.refresh_token
  end
end
