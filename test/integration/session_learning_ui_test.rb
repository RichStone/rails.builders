require "test_helper"

class SessionLearningUiTest < ActionDispatch::IntegrationTest
  setup do
    @facilitator = User.create!(email: "facilitator@example.com", name: "Rich", facilitator: true, enrollment_status: "active", verified_at: Time.current)
    @builder = User.create!(email: "ada@example.com", name: "Ada", enrollment_status: "active", verified_at: Time.current)
    @peer = User.create!(email: "grace@example.com", name: "Grace", enrollment_status: "active", verified_at: Time.current)
    @program = Program.create!(name: "Continuous", starts_on: Date.new(2026, 8, 1), ends_on: Date.new(2026, 12, 31), capacity: 9, main_facilitator: @facilitator)
    @session = completed_session("weekly-learning", Time.zone.parse("2026-09-03 15:30"))
    @session.create_transcript!(state: "ready", source: "manual", content: "Ada: Ship the smaller onboarding flow.", summary_notes: "## Notes\n\nKeep the useful path.", session_analysis: "## Ada\n\n**Session share:** A smaller onboarding flow.")
    @session.next_session_promises.create!(user: @builder, body: "Test the smaller onboarding flow with three customers.")
    @session.peer_feedbacks.create!(author: @peer, recipient: @builder, body: "Keep the first step small and measure completion.", sentiment: "idea", source: "transcript", source_key: "chat-idea")
    @session.peer_feedbacks.create!(author: @builder, recipient: @peer, body: "Your pricing test makes the tradeoff much clearer.", sentiment: "encouraging", source: "chat", source_key: "chat-encouragement")
    @session.create_chat_log!(content: "Grace: <script>alert('private')</script> Try three customers.", source: "manual", imported_at: Time.current)
  end

  test "members see promises and directed feedback grouped by conversation pair above collapsed sources" do
    sign_in_as(@builder)

    get builder_session_path(@session)

    assert_response :success
    assert_select "[data-session-promises]", text: /Ada.*Test the smaller onboarding flow/m
    assert_select "[data-feedback-pair]", count: 1 do
      assert_select "h3", text: "Ada ↔ Grace"
      assert_select "[data-feedback-direction]", text: "Grace → Ada"
      assert_select "[data-feedback-direction]", text: "Ada → Grace"
      assert_select "[data-feedback-sentiment]", text: /Idea/
      assert_select "[data-feedback-sentiment]", text: /Encouraging/
    end
    assert_select "details[data-session-chat]:not([open])", count: 1
    assert_select "details[data-session-notes]:not([open])", count: 1
    assert_select "details[data-session-transcript]:not([open])", count: 1
    assert_operator response.body.index("data-session-analysis>"), :<, response.body.index("data-session-feedback")
    assert_operator response.body.index("data-session-feedback"), :<, response.body.index("data-session-notes")
    assert_select "[data-session-chat-content]", text: /<script>alert\('private'\)<\/script>/
    assert_select "[data-session-chat-content] script", count: 0
    assert_select "[data-chat-editor]", count: 0
  end

  test "only operators see manual chat intake including while transcript is pending" do
    @session.transcript.update!(state: "processing", content: nil)
    sign_in_as(@facilitator)

    get builder_session_path(@session)

    assert_select "[data-chat-editor] form[action='#{builder_session_chat_log_path(@session)}']" do
      assert_select "textarea[name='builder_session_chat_log[content]']"
      assert_select "input[type='submit'][value='Save meeting chat']"
    end
    assert_select "[data-session-chat-content]", text: /Try three customers/
  end

  test "a deleted transcript cannot reveal or collect related private records" do
    @session.transcript.update!(state: "deleted", content: nil, summary_notes: nil, session_analysis: nil)
    sign_in_as(@facilitator)

    get builder_session_path(@session)

    assert_select "[data-session-promises], [data-session-feedback], [data-session-chat], [data-chat-editor]", count: 0
    assert_not_includes response.body, "Test the smaller onboarding flow"
    assert_not_includes response.body, "Keep the first step small"
    assert_not_includes response.body, "Try three customers"
  end

  test "nonmembers and the homepage cannot access private feedback chat or promises" do
    get builder_session_path(@session)
    assert_redirected_to sign_in_path

    get root_path
    assert_not_includes response.body, "Test the smaller onboarding flow"
    assert_not_includes response.body, "Keep the first step small"
    assert_not_includes response.body, "Try three customers"

    @builder.update!(enrollment_status: "inactive")
    sign_in_as(@builder)
    get builder_session_path(@session)
    assert_redirected_to dashboard_path
  end

  test "the live speaker sees a focus project then last session promise then session questions" do
    @builder.products.create!(name: "Tiny Onboarding", url: "https://example.com/onboarding", focus: true)
    live_session = @program.builder_sessions.create!(google_event_id: "next-week", title: "Next week", scheduled_starts_at: Time.zone.parse("2026-09-10 15:30"), scheduled_ends_at: Time.zone.parse("2026-09-10 16:30"), time_zone: "Europe/Berlin")
    live_session.start!(facilitator: @facilitator)
    live_session.finish_current_speaker! until live_session.current_speaker_attendance.user == @builder
    assert_equal @builder, live_session.current_speaker_attendance.user
    sign_in_as(@builder)

    get builder_session_path(live_session)

    assert_select "[data-speaker-project] a[href='https://example.com/onboarding'][rel='noopener noreferrer']", text: /Tiny Onboarding/
    assert_select "[data-previous-promise]", text: /Test the smaller onboarding flow with three customers/
    assert_select "[data-previous-promise] a[href='#{builder_session_path(@session)}']", text: /Last session/
    assert_operator response.body.index("data-speaker-project"), :<, response.body.index("data-previous-promise")
    assert_operator response.body.index("data-previous-promise"), :<, response.body.index("data-session-prompts")
  end

  private

  def completed_session(event_id, starts_at)
    @program.builder_sessions.create!(google_event_id: event_id, title: "Useful weekly learning", assigned_facilitator: @facilitator, scheduled_starts_at: starts_at, scheduled_ends_at: starts_at + 1.hour, time_zone: "Europe/Berlin", state: "completed", started_at: starts_at, ended_at: starts_at + 1.hour, facilitator_name_snapshot: @facilitator.name).tap do |session|
      [ @facilitator, @builder, @peer ].each do |user|
        session.attendances.create!(user: user, display_name: user.name, role: user.facilitator? ? "facilitator" : "builder", status: "present")
      end
    end
  end

  def sign_in_as(user)
    token = user.reload.generate_token_for(:email_verification)
    get verify_email_path(token: token)
    post verify_email_path, params: { token: token }
  end
end
