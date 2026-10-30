require "application_system_test_case"

class ReauthenticationUiSystemTest < ApplicationSystemTestCase
  include ActiveJob::TestHelper

  setup do
    @admin = User.create!(email: "admin@example.com", name: "Administrator", administrator: true, facilitator: true, verified_at: Time.current)
    program = Program.create!(name: "Continuous", starts_on: Date.current, ends_on: 4.months.from_now.to_date, capacity: 9, main_facilitator: @admin)
    @connection = program.create_calendar_connection!(facilitator: @admin, google_account_email: @admin.email,
      google_calendar_id: "sessions-calendar", google_calendar_name: "Sessions", oauth_token_json: "{}", status: "connected")
  end

  test "notes consent sends one confirmation email and resumes after an explicit same-browser confirmation" do
    authorization_calls = []
    authorization = Object.new
    authorization.define_singleton_method(:authorization_url) do |request:, redirect_to:, login_hint:|
      authorization_calls << { method: request.request_method, redirect_to:, login_hint: }
      "/admin?notes_authorization=started"
    end

    with_stubbed_singleton_method(GoogleWorkspace::Authorization, :new, authorization) do
      visit verify_email_path(token: @admin.generate_token_for(:email_verification))
      assert_current_path dashboard_path
      @admin.login_sessions.sole.update!(created_at: 16.minutes.ago)
      visit admin_root_path

      assert_difference -> { ActionMailer::Base.deliveries.size }, 1 do
        perform_enqueued_jobs only: UserMailer.delivery_job do
          click_button_and_wait_for_navigation "Allow calendar notes access"
          assert_current_path reauthentication_path
          assert_text "We’ve emailed you a confirmation link."
          assert_button "Resend confirmation email"
        end
      end
      assert_empty authorization_calls
      assert_equal "connected", @connection.reload.status

      assert_no_enqueued_jobs only: UserMailer.delivery_job do
        page.refresh
        assert_text "We’ve emailed you a confirmation link."
        assert_button "Resend confirmation email"
      end
      page.current_window.resize_to(390, 900)
      assert page.evaluate_script("document.documentElement.scrollWidth <= window.innerWidth"), "The confirmation page should fit a mobile viewport"
      page.save_screenshot(Rails.root.join("tmp/screenshots/reauthentication-mobile.png")) if ENV["REAUTHENTICATION_SCREENSHOTS"] == "1"

      mail = ActionMailer::Base.deliveries.last
      assert_equal [ @admin.email ], mail.to
      url = URI.extract(mail.text_part.body.decoded).find { |value| value.include?("/reauthentication/edit") }
      assert url, "The confirmation email should link to the identity confirmation page"
      visit URI(url).request_uri
      assert_text "Confirm your identity."
      assert_button "Confirm identity"
      assert_empty authorization_calls

      click_button_and_wait_for_navigation "Confirm identity"
      assert_current_path "/admin?notes_authorization=started"
      assert_equal [ { method: "GET", redirect_to: admin_calendar_connection_path, login_hint: @admin.email } ], authorization_calls
      assert @admin.login_sessions.sole.recently_authenticated?
      assert_equal "sessions-calendar", @connection.reload.google_calendar_id
    end
  ensure
    page.current_window.resize_to(1280, 900)
  end
end
