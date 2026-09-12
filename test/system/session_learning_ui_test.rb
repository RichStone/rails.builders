require "application_system_test_case"

class SessionLearningUiSystemTest < ApplicationSystemTestCase
  setup do
    @facilitator = User.create!(email: "facilitator@example.com", name: "Rich", facilitator: true, enrollment_status: "active", verified_at: Time.current)
    @builder = User.create!(email: "ada@example.com", name: "Ada", enrollment_status: "active", verified_at: Time.current)
    @program = Program.create!(name: "Continuous", starts_on: Date.current, ends_on: 4.months.from_now.to_date, capacity: 9, main_facilitator: @facilitator)
    starts_at = 7.days.ago
    @session = @program.builder_sessions.create!(google_event_id: "learning-browser", title: "Small bets, better onboarding", assigned_facilitator: @facilitator, scheduled_starts_at: starts_at, scheduled_ends_at: starts_at + 1.hour, time_zone: "Europe/Berlin", state: "completed", started_at: starts_at, ended_at: starts_at + 1.hour, facilitator_name_snapshot: "Rich")
    @session.attendances.create!(user: @builder, display_name: "Ada", role: "builder", status: "present")
    @session.attendances.create!(user: @facilitator, display_name: "Rich", role: "facilitator", status: "present")
    @session.create_transcript!(state: "ready", source: "manual", content: "Ada: I will test the smaller onboarding flow with three customers.", summary_notes: "## The useful signal\n\nThree real conversations beat another speculative feature.", session_analysis: "## Ada\n\n**Current project:** Tiny Onboarding\n\n**Session share:** Cut onboarding from seven steps to three.\n\n**Latest trend:** Moved from building features to testing the first customer experience.")
    @session.next_session_promises.create!(user: @builder, body: "Test the smaller onboarding flow with three customers.")
    @session.next_session_promises.create!(user: @facilitator, body: "Ask five builders what would make their next week easier.")
    @session.peer_feedbacks.create!(author: @facilitator, recipient: @builder, body: "Show the outcome before the setup. Watch where the first three customers hesitate.", sentiment: "idea", source: "transcript", source_key: "feedback-1")
    @session.peer_feedbacks.create!(author: @builder, recipient: @facilitator, body: "The weekly commitment made it much easier to choose what not to build.", sentiment: "encouraging", source: "chat", source_key: "feedback-2")
    @session.create_chat_log!(content: "Rich: Try the shorter path with three real customers.", source: "manual", imported_at: Time.current)
  end

  test "members read conversation pairs and operators can paste the private meeting chat" do
    sign_in_as(@facilitator)
    visit builder_session_path(@session)

    assert_selector "[data-feedback-pair] h3", text: "Ada ↔ Rich"
    assert_selector "[data-feedback-direction]", text: "Rich → Ada"
    assert_selector "[data-feedback-direction]", text: "Ada → Rich"
    assert_no_selector "details[data-session-chat][open]"
    assert_no_selector "details[data-session-notes][open]"
    capture_learning_screenshot("session-learning-desktop", "[data-session-promises]")

    page.current_window.resize_to(390, 1000)
    assert_no_horizontal_overflow
    capture_learning_screenshot("session-learning-mobile", "[data-session-feedback]")

    find("[data-session-chat] > summary").click
    assert_selector "[data-session-chat-content]", text: "Try the shorter path"
    find("[data-chat-editor] > summary").click
    fill_in "Meeting chat text", with: "Rich [17:42]: Three customers is a useful first test.\nAda [17:43]: That is my next step!"
    click_button "Save meeting chat"

    assert_text "Meeting chat saved."
    find("[data-session-chat] > summary").click
    assert_selector "[data-session-chat-content]", text: "That is my next step!"
  ensure
    page.current_window.resize_to(1280, 900)
  end

  test "the current speaker has a readable emphasized promise and project on desktop and mobile" do
    @builder.products.create!(name: "Tiny Onboarding", url: "https://example.com/onboarding", focus: true)
    live_session = @program.builder_sessions.create!(google_event_id: "live-learning-browser", title: "One useful next move", scheduled_starts_at: Time.current, scheduled_ends_at: 1.hour.from_now, time_zone: "Europe/Berlin")
    live_session.start!(facilitator: @facilitator)
    live_session.finish_current_speaker! until live_session.current_speaker_attendance.user == @builder
    sign_in_as(@builder)

    visit builder_session_path(live_session)

    assert_link "Tiny Onboarding", href: "https://example.com/onboarding"
    assert_selector "[data-previous-promise]", text: "Test the smaller onboarding flow with three customers."
    assert_selector "[data-session-prompts]", text: "One business challenge"
    capture_learning_screenshot("session-live-promise-desktop", ".live-session-stage")

    page.current_window.resize_to(390, 1000)
    assert_no_horizontal_overflow
    capture_learning_screenshot("session-live-promise-mobile", ".live-session-stage")
  ensure
    page.current_window.resize_to(1280, 900)
  end

  private

  def sign_in_as(user)
    visit verify_email_path(token: user.reload.generate_token_for(:email_verification))
    assert_current_path dashboard_path
  end

  def assert_no_horizontal_overflow
    assert page.evaluate_script("document.documentElement.scrollWidth <= window.innerWidth"), "The session page should fit the viewport"
  end

  def capture_learning_screenshot(name, selector)
    return unless ENV["SESSION_LEARNING_SCREENSHOTS"] == "1"

    page.execute_script("arguments[0].scrollIntoView({ block: 'start', behavior: 'instant' })", find(selector))
    page.save_screenshot(Rails.root.join("tmp/screenshots/#{name}.png"))
  end
end
