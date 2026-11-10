require "test_helper"

class BuilderAwardsTest < ActionDispatch::IntegrationTest
  test "a facilitator prepares awards privately and reveals them at the end of the session" do
    facilitator = User.create!(email: "facilitator@example.com", name: "Rich", facilitator: true, enrollment_status: "active", verified_at: Time.current)
    builder = User.create!(email: "builder@example.com", name: "Ralph", enrollment_status: "active", verified_at: Time.current)
    program = Program.create!(name: "Continuous", starts_on: Date.current - 60, ends_on: Date.current + 30, capacity: 9, main_facilitator: facilitator)
    source = create_builder_session(program, "First update", 7.days.ago, state: "completed")
    ceremony = create_builder_session(program, "Halfway session", Time.current)
    award = { user_id: builder.id, title: "Best Customer Discovery", citation: "Found customers through several versions of his marketing site.", evidence_session_id: source.id }

    sign_in_as(facilitator)
    post builder_session_awards_path(ceremony), params: { builder_award: award }
    follow_redirect!
    assert_select "[data-award-drafts]", text: /Best Customer Discovery/
    assert_select "[data-award-drafts] a[href='#{builder_session_path(source)}']"
    patch reveal_builder_session_awards_path(ceremony)

    sign_in_as(builder)
    get builder_session_path(ceremony)
    assert_not_includes response.body, award[:title]
    get edit_profile_path
    assert_not_includes response.body, award[:title]
    patch reveal_builder_session_awards_path(ceremony)
    assert_redirected_to builder_sessions_path

    sign_in_as(facilitator)
    ceremony.start!(facilitator:)
    ceremony.advance_phase!
    get builder_session_path(ceremony)
    version = css_select("form[action='#{reveal_builder_session_awards_path(ceremony)}'] input[name='version']").first["value"]
    patch reveal_builder_session_awards_path(ceremony), params: { version: }
    assert_redirected_to builder_session_path(ceremony, anchor: "awards")
    post cancel_start_builder_session_path(ceremony), params: { run_started_at: ceremony.reload.run_token }
    get builder_session_path(ceremony)
    assert_select "[data-session-awards] a[href='#{builder_session_path(source)}']"
    assert_select "form[action='#{cancel_start_builder_session_path(ceremony)}']", count: 0

    sign_in_as(builder)
    get builder_session_path(ceremony)
    assert_select "[data-session-awards]", text: /Best Customer Discovery.*Ralph.*Found customers/m
    assert_select "[data-award-drafts], [data-session-awards] a", count: 0
    get edit_profile_path
    assert_select "[data-builder-awards] a[href='#{builder_session_path(ceremony, anchor: "awards")}']", text: /Halfway session/
    get root_path
    assert_not_includes response.body, award[:title]
  end

  private

  def create_builder_session(program, title, start, state: "ready")
    program.builder_sessions.create!(google_event_id: title, title:, state:, scheduled_starts_at: start, scheduled_ends_at: start + 90.minutes, time_zone: "Europe/Madrid", assigned_facilitator: program.main_facilitator)
  end

  def sign_in_as(user)
    token = user.reload.generate_token_for(:email_verification)
    get verify_email_path(token: token)
    post verify_email_path, params: { token: token }
  end
end
