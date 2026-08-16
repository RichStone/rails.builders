require "application_system_test_case"

class RegistrationTest < ApplicationSystemTestCase
  setup do
    Program.create!(name: "Continuous", starts_on: Date.new(2026, 8, 20), ends_on: Date.new(2026, 12, 17), capacity: 10)
  end

  test "visitor verifies an email and sees an exact waitlist position" do
    visit root_path
    assert_text "Build in public."
    click_link "Claim your place"
    fill_in "Email address", with: "browser@example.com"
    click_button "Email me a secure link"
    assert_text "Go check your inbox."

    user = User.find_by!(email: "browser@example.com")
    visit verify_email_path(token: user.generate_token_for(:email_verification))
    click_button "Sign in"

    assert_text "You’re on the waitlist."
    assert_text "#1"
    assert_link "Profile"
  end
end
