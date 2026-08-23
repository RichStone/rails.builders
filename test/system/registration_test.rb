require "application_system_test_case"

class RegistrationTest < ApplicationSystemTestCase
  setup do
    Program.create!(name: "Continuous", starts_on: Date.new(2026, 8, 20), ends_on: Date.new(2026, 12, 17), capacity: 10)
  end

  test "visitor verifies an email, confirms readiness, and sees an exact waitlist position" do
    visit root_path
    assert_text "Build in public with other Rails.Builders"
    click_link "Claim your place"
    fill_in "Email address", with: "browser@example.com"
    click_button "Email me a secure link"
    assert_text "Go check your inbox."

    user = User.find_by!(email: "browser@example.com")
    visit verify_email_path(token: user.generate_token_for(:email_verification))
    click_button "Sign in"

    assert_text "Your account is ready."
    within("[data-waitlist-readiness]") do
      assert_no_text "Join the waitlist"
      all(".readiness-item label").each(&:click)
      assert_text "Join the waitlist"
      find(".membership-activation label").click
      click_button "Join the waitlist"
    end

    assert_text "You’re on the waitlist."
    assert_text "#1"
    within("[data-waitlist-readiness]") do
      assert_selector "input[name='readiness[]']:checked", count: 6, visible: :all

      find(".membership-activation label").click
      assert_no_selector "input[name='readiness[]']:checked", visible: :all

      find(".membership-activation label").click
      assert_selector "input[name='readiness[]']:checked", count: 6, visible: :all
    end
    assert_link "Profile"
  end

  test "visitor unlocks the join button by checking every readiness point" do
    visit root_path

    find("#readiness summary").click
    within("#readiness") do
      assert_no_link "Bring me in 🤝"
      all(".readiness-item label").each(&:click)
      assert_link "Bring me in 🤝"
      assert_selector ".readiness-confetti", minimum: 1
    end
  end

  test "offered builder unlocks Active Builder status with the readiness checklist" do
    user = User.create!(email: "og-ready@example.com", og: true)
    visit verify_email_path(token: user.generate_token_for(:email_verification))
    click_button "Sign in"

    within(".membership-panel") do
      assert_no_text "I’m an Active Builder"
      all(".readiness-item label").each(&:click)
      assert_text "I’m an Active Builder"
      find(".membership-activation label").click
      click_button "Confirm Active Builder"
    end

    assert_text "You’re an active builder."
    assert user.reload.active?
    within(".membership-panel") do
      assert_no_selector "input[name='readiness[]']:checked", visible: :all
    end
  end
end
