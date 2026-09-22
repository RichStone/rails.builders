require "application_system_test_case"

class NotificationPreferencesSystemTest < ApplicationSystemTestCase
  test "a builder opens the email destination and saves notification preferences on mobile" do
    user = User.create!(email: "builder@example.com", verified_at: Time.current, enrollment_status: "active")
    visit notification_preferences_path
    assert_text "Sign in"
    visit verify_email_path(token: user.generate_token_for(:email_verification))
    assert_text "Configure your notifications"

    page.driver.browser.execute_cdp("Emulation.setDeviceMetricsOverride", width: 390, height: 844, deviceScaleFactor: 1, mobile: true)
    uncheck "Enrollment notifications"
    fill_in "Remind me this many hours before the session", with: "2"
    click_button_and_wait_for_navigation "Save preferences"
    assert_text "Your notification preferences are saved."
    assert_unchecked_field "Enrollment notifications"
    assert_checked_field "Session reminders"
    assert_field "Remind me this many hours before the session", with: "2"

    uncheck "All notifications"
    click_button_and_wait_for_navigation "Save preferences"
    assert_text "Your notification preferences are saved."
    assert_unchecked_field "All notifications"
    assert_checked_field "Session reminders"
    visit notification_preferences_path
    assert_unchecked_field "All notifications"
    assert_unchecked_field "Enrollment notifications"
    assert_field "Remind me this many hours before the session", with: "2"
    assert_operator page.evaluate_script("document.documentElement.scrollWidth"), :<=, 390
    page.execute_script("window.scrollTo(0, 0)")
    page.save_screenshot(Rails.root.join("tmp/notification-preferences-mobile.png"))
  ensure
    page.driver.browser.execute_cdp("Emulation.clearDeviceMetricsOverride")
  end
end
