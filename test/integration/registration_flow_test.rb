require "test_helper"

class RegistrationFlowTest < ActionDispatch::IntegrationTest
  setup do
    @program = Program.create!(name: "Continuous", starts_on: Date.new(2026, 8, 20), ends_on: Date.new(2026, 12, 17), capacity: 10)
  end

  test "a new email verifies without entering the waitlist before the readiness check" do
    assert_emails 1 do
      post sign_in_path, params: { email: "new@example.com" }
    end

    user = User.find_by!(email: "new@example.com")
    assert_nil user.newsletter_requested_at
    assert_redirected_to check_email_path

    token = user.generate_token_for(:email_verification)
    get verify_email_path(token: token)

    assert_response :success
    assert_not user.reload.verified?
    assert_select "form[action='#{verify_email_path}']"

    post verify_email_path, params: { token: token }

    assert_redirected_to dashboard_path
    assert_equal "inactive", user.reload.enrollment_status
    follow_redirect!
    assert_equal "no-store", response.headers["Cache-Control"]
    assert_select "h1", /Your account is ready/
    assert_select "input[name='readiness[]']", count: 6
    assert_select "[data-waitlist-readiness] [data-readiness-checklist-target='activation'][hidden]"
    assert_select "a", "Sign out"

    post verify_email_path, params: { token: token }
    assert_redirected_to sign_in_path
  end

  test "sign-in requests are throttled per email address" do
    5.times do
      post sign_in_path, params: { email: "target@example.com" }
      assert_redirected_to check_email_path
    end

    post sign_in_path, params: { email: " TARGET@example.com " }

    assert_response :too_many_requests
  end

  test "a successful sign-in rejects the pre-authentication CSRF token" do
    previous_forgery_protection = ActionController::Base.allow_forgery_protection
    ActionController::Base.allow_forgery_protection = true
    user = User.create!(email: "returning@example.com")
    verification_token = user.generate_token_for(:email_verification)

    get sign_in_path
    pre_authentication_token = html_document.at_css("meta[name='csrf-token']")["content"]
    post verify_email_path,
      params: { token: verification_token },
      headers: { "X-CSRF-Token" => pre_authentication_token }
    assert_redirected_to dashboard_path

    delete sign_out_path, headers: { "X-CSRF-Token" => pre_authentication_token }
    assert_response :unprocessable_content
  ensure
    ActionController::Base.allow_forgery_protection = previous_forgery_protection
  end

  test "newsletter consent sends a separate confirmation and does not subscribe immediately" do
    assert_emails 2 do
      post sign_in_path, params: { email: "reader@example.com", newsletter_opt_in: "1" }
    end

    user = User.find_by!(email: "reader@example.com")
    assert user.newsletter_requested_at
    assert_nil user.newsletter_confirmed_at

    token = user.generate_token_for(:newsletter_confirmation)
    get confirm_newsletter_path(token: token)

    assert_response :success
    assert_nil user.reload.newsletter_confirmed_at
    assert_select "form[action='#{confirm_newsletter_path}']"

    post confirm_newsletter_path, params: { token: token }

    assert_redirected_to sign_in_path
    assert user.reload.newsletter_confirmed_at
    assert_not user.verified?

    post confirm_newsletter_path, params: { token: token }
    assert_redirected_to root_path
  end

  test "an OG receives a seat offer after verification" do
    user = User.create!(email: "og@example.com", og: true)
    post sign_in_path, params: { email: user.email }

    token = user.reload.generate_token_for(:email_verification)
    get verify_email_path(token: token)
    post verify_email_path, params: { token: token }

    assert_equal "offered", user.reload.enrollment_status
    follow_redirect!
    assert_select "h1", /Your seat is ready/
    assert_select "input[name='readiness[]']", count: 6
    assert_select "[data-readiness-checklist-target='activation'][hidden]"
    assert_select "form", text: /Accept Seat Offer/, count: 0
  end

  test "general admission sends one offer outcome rather than a transient waitlist email" do
    @program.update!(og_priority: false)
    user = User.create!(email: "general@example.com")
    clear_enqueued_jobs
    ActionMailer::Base.deliveries.clear

    perform_enqueued_jobs do
      token = user.reload.generate_token_for(:email_verification)
      get verify_email_path(token: token)
      post verify_email_path, params: { token: token }
      patch waitlist_path, params: { joined: "1", readiness: %w[0 1 2 3 4 5] }
    end

    assert user.reload.offered?
    subjects = ActionMailer::Base.deliveries.map(&:subject)
    assert_not_includes subjects, "You’re on the Rails Builders waitlist"
    assert_equal 1, subjects.count("A Rails Builders seat is yours to confirm")
  end
end
