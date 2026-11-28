require "application_system_test_case"

class RegistrationTest < ApplicationSystemTestCase
  setup do
    Program.create!(name: "Continuous", starts_on: Date.new(2026, 8, 20), ends_on: Date.new(2026, 12, 17), capacity: 10)
  end

  test "visitor verifies an email, confirms readiness, and sees an exact waitlist position" do
    Program.current.update!(capacity: 1)
    User.create!(email: "occupying@example.com", verified_at: Time.current, enrollment_status: "active")

    visit root_path
    assert_text "Build in public with other Rails.Builders"
    within(".site-header") { click_link "Join" }
    assert_current_path join_path
    assert_unchecked_field "newsletter_opt_in"
    fill_in "Email address", with: "browser@example.com"
    travel 3.seconds
    click_button "Email me a secure link"
    assert_text "Go check your inbox."

    user = User.find_by!(email: "browser@example.com")
    visit verify_email_path(token: user.generate_token_for(:email_verification))

    assert_text "Your account is ready."
    within("[data-waitlist-readiness]") do
      assert_no_selector ".membership-activation:not([hidden])"
      all(".readiness-item label").each(&:click)
      assert_selector ".membership-activation:not([hidden])"
      # Wait for the entrance animation so the label does not move during the click.
      assert_selector ".membership-activation", style: { opacity: "1" }
      find(".membership-activation label").click
      assert_text "Ready to join Builders?"
      click_button "Join Builders"
    end

    assert_text "You’re on the waitlist."
    assert_text "#1"
    within("[data-waitlist-readiness]") do
      assert_no_selector "input[name='readiness[]']", visible: :all

      find(".membership-activation label").click
      assert_no_selector "input[name='readiness[]']:checked", visible: :all
      assert_text "You’ll lose position #1 in the waitlist."
      click_button "Keep my spot"
      assert_selector "input[name='joined']:checked", visible: :all
      assert_no_selector "input[name='readiness[]']", visible: :all
    end
    assert_link "Profile"
  end
end
