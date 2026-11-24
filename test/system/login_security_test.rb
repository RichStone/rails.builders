require "application_system_test_case"

class LoginSecuritySystemTest < ApplicationSystemTestCase
  include ActiveJob::TestHelper

  setup do
    Program.create!(name: "Continuous", starts_on: Date.new(2026, 8, 20), ends_on: Date.new(2026, 12, 17), capacity: 10)
    @admin = User.create!(email: "admin@example.com", verified_at: Time.current, administrator: true)
    @builder = User.create!(email: "builder@example.com", verified_at: Time.current)
  end

  test "an administrator confirms by email before retrying a sensitive change" do
    visit verify_email_path(token: @admin.generate_token_for(:email_verification))
    assert_current_path dashboard_path
    travel 16.minutes
    visit edit_admin_user_path(@builder)
    perform_enqueued_jobs do
      accept_confirm { click_button "Grant Administrator role" }
      assert_text "We’ve emailed you a confirmation link."
    end
    assert_button "Resend confirmation email"
    assert_not @builder.reload.administrator?
    mail = ActionMailer::Base.deliveries.last
    url = URI.extract(mail.text_part.body.decoded).find { |value| value.include?("/reauthentication/edit") }
    visit URI(url).request_uri
    assert_text "Confirm your identity."
    click_button "Confirm identity"
    assert_text "Email confirmed."
    visit edit_admin_user_path(@builder)
    accept_confirm { click_button "Grant Administrator role" }
    assert_text "Administrator role granted."
    assert @builder.reload.administrator?
  end

  test "a Builder promotion can be retried after email confirmation in another tab" do
    previous_forgery_protection = ActionController::Base.allow_forgery_protection
    ActionController::Base.allow_forgery_protection = true
    @builder.issue_offer!

    visit verify_email_path(token: @admin.generate_token_for(:email_verification))
    assert_current_path dashboard_path
    visit builder_path(@builder)
    assert_text "Status: Offered"
    travel 16.minutes

    within_window(open_new_window) do
      token = @admin.login_sessions.sole.generate_token_for(:reauthentication)
      visit edit_reauthentication_path(token: token)
      click_button "Confirm identity"
      assert_text "Email confirmed."
    end

    accept_confirm { click_button "Promote to Active Builder" }
    assert_text "This form has expired. Review the options and try again."
    assert_text "Status: Offered"
    assert @builder.reload.offered?

    accept_confirm { click_button "Promote to Active Builder" }
    assert_text "Builder promoted to Active Builder."
    assert_text "Status: Active"
    assert @builder.reload.active?
  ensure
    ActionController::Base.allow_forgery_protection = previous_forgery_protection
  end

  test "a builder can sign out all devices from their profile" do
    visit verify_email_path(token: @builder.generate_token_for(:email_verification))
    assert_current_path dashboard_path
    click_link "Profile"
    accept_confirm { click_button "Sign out all devices" }
    assert_text "You’re signed out on all devices."
    visit dashboard_path
    assert_current_path sign_in_path
  end
end
