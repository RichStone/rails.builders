require "application_system_test_case"

class BuilderSessionsSystemTest < ApplicationSystemTestCase
  setup do
    @facilitator = User.create!(
      email: "facilitator@example.com",
      name: "Session Facilitator",
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
    @program = Program.create!(
      name: "Continuous",
      starts_on: Date.current,
      ends_on: 4.months.from_now.to_date,
      capacity: 9,
      main_facilitator: @facilitator
    )
    @builder_session = @program.builder_sessions.create!(
      assigned_facilitator: @facilitator,
      google_event_id: "browser-session",
      title: "Browser session",
      meet_url: "https://meet.google.com/abc-defg-hij",
      scheduled_starts_at: 10.minutes.from_now,
      scheduled_ends_at: 40.minutes.from_now,
      time_zone: "Europe/Madrid"
    )
  end

  test "public schedule becomes a shared live room with role-specific controls" do
    visit root_path
    assert_text "Browser session"
    assert_no_text "abc-defg-hij"

    sign_in_as(@builder)
    click_link "Sessions"
    click_link "Browser session"
    assert_link "Join Google Meet"
    assert_no_button "Start session"

    click_link "Sign out"
    sign_in_as(@facilitator)
    click_link "Sessions"
    click_link "Browser session"
    fill_in "Formal timer (minutes)", with: "30"
    click_button "Start session"

    assert_text "What did you ship—or learn—since we last met?"
    assert_button "Pause"
    within(".attendance-row", text: "Active Builder") { click_button "Mark present" }
    click_button "Start builder updates"
    assert_selector ".live-phase", text: /builder updates/i
    assert_text "Active Builder"
    assert_button "Speaker complete"

    click_button "Pause"
    assert_button "Resume"
    click_button "Resume", exact: true
    assert_button "Pause"
    accept_confirm("Finish this session now?") { click_button "Finish session" }
    assert_text(/session complete/i)
    assert_text "Processing transcript"
  end

  private

  def sign_in_as(user)
    visit verify_email_path(token: user.reload.generate_token_for(:email_verification))
  end
end
