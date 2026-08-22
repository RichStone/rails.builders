require "test_helper"

class BuilderSessionsTest < ActionDispatch::IntegrationTest
  setup do
    @facilitator = User.create!(
      email: "facilitator@example.com",
      name: "Main Facilitator",
      facilitator: true,
      enrollment_status: "active",
      verified_at: Time.current
    )
    @builder = User.create!(
      email: "builder@example.com",
      name: "Active Builder",
      enrollment_status: "active",
      verified_at: Time.current
    )
    @waitlisted = User.create!(
      email: "waiting@example.com",
      name: "Waiting Builder",
      enrollment_status: "waitlisted",
      waitlist_rank: 1,
      waitlist_joined_at: Time.current,
      verified_at: Time.current
    )
    @program = Program.create!(
      name: "Continuous",
      starts_on: Date.new(2026, 8, 20),
      ends_on: Date.new(2026, 12, 17),
      capacity: 9,
      main_facilitator: @facilitator
    )
    @builder_session = @program.builder_sessions.create!(
      assigned_facilitator: @facilitator,
      google_event_id: "calendar-event-1",
      title: "Product teardown",
      description: "A focused session. Join at https://meet.google.com/private-code",
      meet_url: "https://meet.google.com/abc-defg-hij",
      scheduled_starts_at: Time.zone.parse("2026-08-24 18:00"),
      scheduled_ends_at: Time.zone.parse("2026-08-24 19:00"),
      time_zone: "Europe/Madrid"
    )
  end

  test "the homepage shows an upcoming session without private session data" do
    @builder_session.update!(title: "Product teardown · meet.google.com/abc-defg-hij")

    get root_path

    assert_response :success
    assert_select "[data-public-sessions]", text: /Product teardown/
    assert_select "[data-public-sessions]", text: /Facilitated by Rails Builders/
    assert_not_includes response.body, "Main Facilitator"
    assert_not_includes response.body, "abc-defg-hij"
    assert_not_includes response.body, "private-code"
    assert_not_includes response.body, @builder.email
  end

  test "the public live banner does not reveal private people or meeting links" do
    @builder_session.update!(title: "Live teardown · https://meet.google.com/abc-defg-hij")
    @builder_session.start!(facilitator: @facilitator)

    get root_path

    assert_select ".live-session-banner", text: /Live now/
    assert_select ".live-session-banner", text: /Facilitated by Rails Builders/
    assert_select ".live-session-banner a", count: 0
    public_sessions = css_select("[data-public-sessions]").to_s
    assert_not_includes public_sessions, "abc-defg-hij"
    assert_not_includes public_sessions, "Main Facilitator"
    assert_not_includes public_sessions, "Active Builder"
  end

  test "active Builders can see private session details" do
    sign_in_as(@builder)

    get builder_sessions_path
    assert_response :success
    assert_select "a", text: "Product teardown"

    get builder_session_path(@builder_session)
    assert_response :success
    assert_equal "no-store", response.headers["Cache-Control"]
    assert_select "meta[name='turbo-cache-control'][content='no-cache']"
    assert_select "a[href='#{join_builder_session_path(@builder_session)}']", text: /Join Google Meet/
    assert_select "[data-session-controls]", count: 0

    get join_builder_session_path(@builder_session)
    assert_redirected_to "https://meet.google.com/abc-defg-hij"
    assert_equal "no-store", response.headers["Cache-Control"]
    assert_equal "[FILTERED]", response.filtered_location
  end

  test "cancelled and completed sessions cannot be joined" do
    sign_in_as(@builder)

    @builder_session.update!(state: "cancelled")
    get builder_session_path(@builder_session)
    assert_select "a", text: /Join Google Meet/, count: 0
    get join_builder_session_path(@builder_session)
    assert_redirected_to builder_session_path(@builder_session)

    @builder_session.update!(state: "ready")
    @builder_session.start!(facilitator: @facilitator)
    @builder_session.finish!
    get builder_session_path(@builder_session)
    assert_select "a", text: /Join Google Meet/, count: 0
    get join_builder_session_path(@builder_session)
    assert_redirected_to builder_session_path(@builder_session)
  end

  test "a missed ready session appears in Past instead of Upcoming" do
    sign_in_as(@builder)

    travel_to(@builder_session.scheduled_starts_at + 1.minute) do
      get builder_sessions_path
    end

    sections = css_select("section.session-section")
    upcoming = sections.find { |section| section.at_css("h2")&.text == "Upcoming" }
    past = sections.find { |section| section.at_css("h2")&.text == "Past" }
    assert_not_includes upcoming.text, "Product teardown"
    assert_includes past.text, "Product teardown"
  end

  test "visitors and waitlisted users cannot open private sessions" do
    get builder_sessions_path
    assert_redirected_to sign_in_path

    sign_in_as(@waitlisted)
    get builder_sessions_path
    assert_redirected_to dashboard_path
  end

  test "facilitators operate attendance and the live session while Builders can only view" do
    sign_in_as(@builder)
    post start_builder_session_path(@builder_session), params: { duration_minutes: 45 }
    assert_redirected_to builder_sessions_path
    assert_equal "ready", @builder_session.reload.state

    delete sign_out_path
    sign_in_as(@facilitator)
    post start_builder_session_path(@builder_session), params: { duration_minutes: 45 }
    assert_redirected_to builder_session_path(@builder_session)
    assert_equal "connection", @builder_session.reload.state
    assert_equal 45.minutes.to_i, @builder_session.timer_duration_seconds

    get builder_session_path(@builder_session)
    assert_select "[data-controller='session-timer']"
    assert_select "[data-session-controls]"
    assert_select "form[action='#{pause_builder_session_path(@builder_session)}']"

    patch attendance_builder_session_path(@builder_session), params: { user_id: @builder.id, status: "present" }
    assert_equal "present", @builder_session.attendances.find_by!(user: @builder).status

    post advance_builder_session_path(@builder_session)
    assert_equal "builder_updates", @builder_session.reload.state
    post pause_builder_session_path(@builder_session)
    assert @builder_session.paused?
    post resume_builder_session_path(@builder_session)
    assert_not @builder_session.paused?
    post next_speaker_builder_session_path(@builder_session)
    assert_equal "closing", @builder_session.reload.state
    post advance_builder_session_path(@builder_session)
    assert_equal "hangout", @builder_session.reload.state
    post finish_builder_session_path(@builder_session)
    assert_equal "completed", @builder_session.reload.state
  end

  test "facilitators drag the complete unspoken queue into a new order" do
    second_builder = User.create!(email: "second@example.com", name: "Second Builder", enrollment_status: "active", verified_at: Time.current)
    third_builder = User.create!(email: "third@example.com", name: "Third Builder", enrollment_status: "active", verified_at: Time.current)
    @builder_session.start!(facilitator: @facilitator)
    [ @builder, second_builder, third_builder ].each { |builder| @builder_session.mark_present!(builder) }
    @builder_session.advance_phase!
    requested_order = @builder_session.unspoken_speakers.pluck(:id).reverse
    sign_in_as(@facilitator)

    get builder_session_path(@builder_session)
    assert_select "[data-controller~='speaker-order']"
    assert_select "[data-speaker-order-target='item']", count: 2

    patch speaker_order_builder_session_path(@builder_session), params: { attendance_ids: requested_order }, as: :json

    assert_response :no_content
    assert_equal requested_order, @builder_session.unspoken_speakers.pluck(:id)

    patch speaker_order_builder_session_path(@builder_session),
      params: { attendance_ids: [ requested_order.first, requested_order.first ] },
      as: :json
    assert_response :unprocessable_entity
    assert_equal requested_order, @builder_session.unspoken_speakers.pluck(:id)
  end

  test "Builders see a static queue while Administrators may reorder it" do
    second_builder = User.create!(email: "second@example.com", name: "Second Builder", enrollment_status: "active", verified_at: Time.current)
    third_builder = User.create!(email: "third@example.com", name: "Third Builder", enrollment_status: "active", verified_at: Time.current)
    @builder_session.start!(facilitator: @facilitator)
    [ @builder, second_builder, third_builder ].each { |builder| @builder_session.mark_present!(builder) }
    @builder_session.advance_phase!
    original_order = @builder_session.unspoken_speakers.pluck(:id)
    requested_order = original_order.reverse
    sign_in_as(@builder)

    get builder_session_path(@builder_session)
    assert_select "[data-controller~='speaker-order']", count: 0
    assert_select "[draggable='true'][data-action*='speaker-order']", count: 0

    patch speaker_order_builder_session_path(@builder_session), params: { attendance_ids: requested_order }, as: :json
    assert_redirected_to builder_sessions_path
    assert_equal original_order, @builder_session.unspoken_speakers.pluck(:id)

    delete sign_out_path
    administrator = User.create!(email: "administrator@example.com", name: "Administrator", administrator: true, verified_at: Time.current)
    sign_in_as(administrator)
    patch speaker_order_builder_session_path(@builder_session), params: { attendance_ids: requested_order }, as: :json

    assert_response :no_content
    assert_equal requested_order, @builder_session.unspoken_speakers.pluck(:id)
  end

  test "completed transcripts are private, read-only, and support facilitator fallback plus Administrator deletion" do
    travel_to(Time.zone.parse("2026-08-24 18:00")) { @builder_session.start!(facilitator: @facilitator) }
    travel_to(Time.zone.parse("2026-08-24 19:00")) { @builder_session.finish! }
    transcript = @builder_session.reload.transcript

    sign_in_as(@facilitator)
    post builder_session_transcript_path(@builder_session), params: {
      transcript: { content: "Ada\n<script>alert('nope')</script>\n<a href='https://example.com'>click</a>\n<img src='/up'>" }
    }
    assert_redirected_to builder_session_path(@builder_session)
    assert_equal "manual", transcript.reload.source
    assert_equal "ready", transcript.state

    get builder_session_path(@builder_session)
    assert_select "[data-session-transcript]", text: /Ada/
    assert_select "[data-session-transcript] a", count: 0
    assert_select "[data-session-transcript] img", count: 0
    assert_includes response.body, "&lt;script&gt;"
    assert_includes response.body, "&lt;a href="
    assert_includes response.body, "&lt;img src="
    assert_select "textarea[name='transcript[content]']", count: 0

    admin = User.create!(email: "admin@example.com", name: "Administrator", administrator: true, verified_at: Time.current)
    delete sign_out_path
    sign_in_as(admin)
    delete builder_session_transcript_path(@builder_session)
    assert_equal "deleted", transcript.reload.state
    assert_nil transcript.content
  end

  test "facilitators cannot overwrite ready or deleted transcripts by posting directly" do
    travel_to(Time.zone.parse("2026-08-24 18:00")) { @builder_session.start!(facilitator: @facilitator) }
    travel_to(Time.zone.parse("2026-08-24 19:00")) { @builder_session.finish! }
    transcript = @builder_session.reload.transcript
    transcript.replace_with_manual!("Original notes")
    sign_in_as(@facilitator)

    post builder_session_transcript_path(@builder_session), params: { transcript: { content: "Replacement" } }
    assert_equal "Original notes", transcript.reload.content

    transcript.delete_content!
    post builder_session_transcript_path(@builder_session), params: { transcript: { content: "Resurrected" } }
    assert_equal "deleted", transcript.reload.state
    assert_nil transcript.content
  end

  test "a manual transcript cannot be attached before a session is completed" do
    sign_in_as(@facilitator)

    post builder_session_transcript_path(@builder_session), params: { transcript: { content: "Too early" } }

    assert_redirected_to builder_session_path(@builder_session)
    assert_not @builder_session.reload.transcript
  end

  test "an unavailable automatic transcript shows a clear private fallback state" do
    travel_to(Time.zone.parse("2026-08-24 18:00")) { @builder_session.start!(facilitator: @facilitator) }
    travel_to(Time.zone.parse("2026-08-24 19:00")) { @builder_session.finish! }
    @builder_session.transcript.update!(state: "unavailable")
    sign_in_as(@builder)

    get builder_session_path(@builder_session)

    assert_select ".transcript-processing", text: /Automatic transcript unavailable/
    assert_select ".manual-transcript", count: 0
    assert_select "[data-controller='session-refresh']", count: 0
  end

  test "facilitators correct an automatic close while Builders cannot" do
    started_at = ActiveSupport::TimeZone["Europe/Madrid"].parse("2026-08-24 18:00")
    travel_to(started_at) { @builder_session.start!(facilitator: @facilitator) }
    travel_to(started_at + 6.hours) { @builder_session.synchronize! }
    sign_in_as(@facilitator)

    patch end_time_builder_session_path(@builder_session), params: { ended_at: "2026-08-24T19:30" }

    assert_redirected_to builder_session_path(@builder_session)
    assert_equal started_at + 90.minutes, @builder_session.reload.ended_at

    delete sign_out_path
    sign_in_as(@builder)
    patch end_time_builder_session_path(@builder_session), params: { ended_at: "2026-08-24T20:00" }

    assert_redirected_to builder_sessions_path
    assert_equal started_at + 90.minutes, @builder_session.reload.ended_at
  end

  private

  def sign_in_as(user)
    token = user.reload.generate_token_for(:email_verification)
    get verify_email_path(token: token)
    post verify_email_path, params: { token: token }
  end
end
