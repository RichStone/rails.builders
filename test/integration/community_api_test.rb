require "test_helper"

class CommunityApiTest < ActionDispatch::IntegrationTest
  setup do
    @member = User.create!(
      email: "member@example.com",
      name: "API Member",
      enrollment_status: "active",
      verified_at: Time.current
    )
    @program = Program.create!(
      name: "Continuous",
      starts_on: Date.new(2026, 8, 20),
      ends_on: Date.new(2026, 12, 17),
      capacity: 9
    )
  end

  test "an active Builder generates a one-time token and revokes it" do
    sign_in_as(@member)

    get dashboard_path
    assert_select "#community-api" do
      assert_select "form[action='#{community_access_token_path}']", text: "Generate API token"
    end

    post community_access_token_path

    assert_response :success
    token = css_select("#community-api-token").first["value"]
    assert_match User::COMMUNITY_API_TOKEN_PATTERN, token
    assert @member.reload.community_api_token?
    assert_not_equal token, @member.community_api_token_digest
    assert_equal Digest::SHA256.hexdigest(token), @member.community_api_token_digest
    assert_select "body", text: /shown only once/i

    get api_v1_community_path, headers: bearer_headers(token)
    assert_response :success

    delete community_access_token_path
    assert_redirected_to dashboard_path
    assert_not @member.reload.community_api_token?

    get api_v1_community_path, headers: bearer_headers(token)
    assert_response :unauthorized
  end

  test "replacing a token immediately invalidates the previous token" do
    sign_in_as(@member)
    old_token = @member.issue_community_api_token!

    post community_access_token_path

    replacement = css_select("#community-api-token").first["value"]
    assert_not_equal old_token, replacement

    get api_v1_community_path, headers: bearer_headers(old_token)
    assert_response :unauthorized
    get api_v1_community_path, headers: bearer_headers(replacement)
    assert_response :success
  end

  test "missing and malformed credentials are rejected without caching" do
    get api_v1_community_path

    assert_response :unauthorized
    assert_equal 'Bearer realm="Rails Builders community API"', response.headers["WWW-Authenticate"]
    assert_equal "no-store", response.headers["Cache-Control"]

    get api_v1_community_path, headers: bearer_headers("not-a-community-token")
    assert_response :unauthorized
  end

  test "a token does not grant access after active membership ends" do
    token = @member.issue_community_api_token!
    @member.update!(enrollment_status: "withdrawn")

    get api_v1_community_path, headers: bearer_headers(token)

    assert_response :forbidden
    assert_equal "Active Builder access is required.", response.parsed_body.fetch("error")
  end

  test "the snapshot exposes only allowlisted public community data" do
    public_builder = User.create!(
      email: "public@example.com",
      name: "Public Builder",
      testimonial: "Shipping every week.",
      enrollment_status: "active",
      verified_at: Time.current
    )
    public_builder.products.create!(name: "Focus App", url: "https://focus.example", focus: true)
    public_builder.products.create!(name: "Side App", url: "https://side.example")
    public_builder.update!(public_profile: true, public_profile_approved: true)

    private_builder = User.create!(
      email: "private@example.com",
      name: "Private Builder",
      enrollment_status: "active",
      verified_at: Time.current
    )
    unapproved_builder = User.create!(
      email: "pending@example.com",
      name: "Pending Profile",
      enrollment_status: "waitlisted",
      waitlist_rank: 1,
      waitlist_joined_at: Time.current,
      verified_at: Time.current
    )
    unapproved_builder.products.create!(name: "Pending App", url: "https://pending.example", focus: true)
    unapproved_builder.update!(public_profile: true)

    past_session = @program.builder_sessions.create!(
      assigned_facilitator: private_builder,
      google_event_id: "private-calendar-event",
      title: "Product teardown · meet.google.com/abc-defg-hij",
      description: "PRIVATE SESSION DESCRIPTION",
      location: "PRIVATE LOCATION",
      meet_url: "https://meet.google.com/abc-defg-hij",
      scheduled_starts_at: 2.weeks.ago,
      scheduled_ends_at: 2.weeks.ago + 1.hour,
      time_zone: "Europe/Berlin",
      state: "completed",
      started_at: 2.weeks.ago,
      ended_at: 2.weeks.ago + 75.minutes
    )
    past_session.attendances.create!(user: public_builder, display_name: public_builder.name, role: "builder", status: "present", arrived_at: 2.weeks.ago)
    past_session.attendances.create!(user: private_builder, display_name: private_builder.name, role: "builder", status: "absent")
    past_session.create_transcript!(
      state: "ready",
      source: "manual",
      content: "PRIVATE TRANSCRIPT",
      summary_notes: "PRIVATE SUMMARY",
      session_analysis: "PRIVATE ANALYSIS"
    )
    past_session.create_chat_log!(source: "manual", content: "PRIVATE CHAT", imported_at: Time.current)

    @program.builder_sessions.create!(
      google_event_id: "future-event",
      title: "Future session",
      scheduled_starts_at: 2.weeks.from_now,
      scheduled_ends_at: 2.weeks.from_now + 1.hour,
      time_zone: "Europe/Berlin"
    )

    token = @member.issue_community_api_token!
    get api_v1_community_path, headers: bearer_headers(token)

    assert_response :success
    assert_equal "no-store", response.headers["Cache-Control"]
    body = response.parsed_body
    community = body.fetch("community")
    assert_equal "Rails Builders", community.fetch("name")
    assert_equal "Continuous", community.dig("program", "name")
    assert_equal 1, community.dig("program", "public_builder_count")
    assert_equal 1, community.dig("program", "past_session_count")

    builders = community.fetch("public_builders")
    assert_equal [ "Public Builder" ], builders.map { |builder| builder.fetch("name") }
    assert_equal "Shipping every week.", builders.first.fetch("testimonial")
    assert_equal [ "Focus App", "Side App" ], builders.first.fetch("products").map { |product| product.fetch("name") }

    sessions = community.fetch("past_sessions")
    assert_equal 1, sessions.size
    assert_equal "Product teardown · Google Meet", sessions.first.fetch("title")
    assert_equal "completed", sessions.first.fetch("status")
    assert_nil sessions.first.fetch("facilitator")
    assert_equal({ "recorded" => 2, "present" => 1, "absent" => 1,
      "public_profiles" => [ { "name" => "Public Builder", "role" => "builder", "status" => "present" } ] },
      sessions.first.fetch("attendance"))

    sensitive_values = [
      "member@example.com", "public@example.com", "private@example.com", "pending@example.com",
      "Private Builder", "Pending Profile", "private-calendar-event", "abc-defg-hij",
      "PRIVATE SESSION DESCRIPTION", "PRIVATE LOCATION", "PRIVATE TRANSCRIPT", "PRIVATE SUMMARY",
      "PRIVATE ANALYSIS", "PRIVATE CHAT"
    ]
    sensitive_values.each { |value| assert_not_includes response.body, value }
    assert_includes body.dig("privacy", "excluded"), "transcripts and chat logs"
  end

  test "inactive users cannot generate a token" do
    @member.update!(enrollment_status: "withdrawn")
    sign_in_as(@member)

    post community_access_token_path

    assert_redirected_to dashboard_path
    assert_equal "Active Builder access is required.", flash[:alert]
    assert_not @member.reload.community_api_token?
  end

  private

  def bearer_headers(token)
    { "Authorization" => "Bearer #{token}" }
  end

  def sign_in_as(user)
    token = user.reload.generate_token_for(:email_verification)
    get verify_email_path(token: token)
    post verify_email_path, params: { token: token }
  end
end
