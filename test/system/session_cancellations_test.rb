require "application_system_test_case"

class SessionCancellationsSystemTest < ApplicationSystemTestCase
  setup do
    @facilitator = User.create!(
      email: "facilitator@example.com", name: "Session Facilitator", facilitator: true,
      enrollment_status: "active", verified_at: Time.current
    )
    @program = Program.create!(
      name: "Continuous", starts_on: Date.current, ends_on: 4.months.from_now.to_date,
      main_facilitator: @facilitator
    )
    @program.create_calendar_connection!(
      facilitator: @facilitator, google_account_email: @facilitator.email,
      google_calendar_id: "sessions@group.calendar.google.com",
      google_calendar_name: "Rails.Builders Sessions", oauth_token_json: "{}", status: "connected"
    )
    @builder_session = @program.builder_sessions.create!(
      google_event_id: "browser-session-occurrence", title: "Browser cancellation session",
      source_calendar_id: "sessions@group.calendar.google.com",
      scheduled_starts_at: 2.days.from_now, scheduled_ends_at: 2.days.from_now + 90.minutes,
      time_zone: "Europe/Amsterdam"
    )
  end

  test "a facilitator reviews the dated cancellation on desktop and mobile before confirming" do
    visit verify_email_path(token: @facilitator.reload.generate_token_for(:email_verification))
    assert_current_path dashboard_path
    visit builder_session_path(@builder_session)

    assert_no_selector ".session-cancellation-panel[open]"
    find(".session-cancellation-panel > summary").send_keys(:enter)
    assert_selector ".session-cancellation-panel[open]"
    assert_text "Other sessions stay scheduled."
    assert_field "Reason to include in the cancellation email", with: ""
    assert_unchecked_field "confirm_cancellation"
    fill_in "Reason to include in the cancellation email", with: "Rich has an important appointment he can’t miss."
    check "confirm_cancellation"
    page.execute_script("arguments[0].scrollIntoView({ block: 'center', behavior: 'instant' })", find(".session-cancellation-panel"))
    page.save_screenshot(Rails.root.join("tmp/screenshots/session-cancellation-desktop.png"))

    page.driver.browser.execute_cdp("Emulation.setDeviceMetricsOverride",
      width: 390, height: 844, deviceScaleFactor: 1, mobile: true)
    assert_selector("html") { page.evaluate_script("window.innerWidth") == 390 }
    page.execute_script("arguments[0].scrollIntoView({ block: 'center', behavior: 'instant' })", find(".session-cancellation-panel"))
    assert page.evaluate_script("document.documentElement.scrollWidth <= window.innerWidth")
    page.save_screenshot(Rails.root.join("tmp/screenshots/session-cancellation-mobile.png"))
    click_button_and_wait_for_navigation "☢ Cancel this session"

    assert_text "This session is no longer scheduled."
    assert_text "Session reminders have stopped."
    assert_selector "[data-session-cancellation-status]", text: "Calendar removal is pending"
    assert_no_selector ".session-cancellation-panel"
    assert_no_button "Start session"
    assert_equal "cancelled", @builder_session.reload.state
  ensure
    page.driver.browser.execute_cdp("Emulation.clearDeviceMetricsOverride")
  end
end
