require "test_helper"

class RegistrationFlowTest < ActionDispatch::IntegrationTest
  setup do
    @program = Program.create!(name: "Continuous", starts_on: Date.new(2026, 8, 20), ends_on: Date.new(2026, 12, 17), capacity: 10)
  end

  test "a filled honeypot creates no account and queues neither confirmation" do
    assert_no_difference "User.count" do
      assert_no_enqueued_emails do
        post sign_in_path, params: { email: "trap@example.com", website: "https://spam.example", newsletter_opt_in: "1" }
      end
    end

    assert_redirected_to check_email_path
  end

  test "signup email challenge and honeypot values are filtered from request diagnostics" do
    post sign_in_path, params: sign_in_params(
      email: "private@example.com", website: "https://private.example", "cf-turnstile-response": "private-challenge"
    )

    %w[email form_token cf-turnstile-response website].each do |parameter|
      assert_equal "[FILTERED]", request.filtered_parameters.fetch(parameter), parameter
    end
  end

  test "a direct request without a signup form creates no account or mail" do
    assert_no_difference "User.count" do
      assert_no_enqueued_emails do
        post sign_in_path, params: { email: "direct@example.com" }
      end
    end

    assert_response :unprocessable_content
    assert_select ".alert", text: /Please try again/
  end

  test "an unusually fast submission preserves input and can be retried after waiting" do
    get sign_in_path
    token = html_document.at_css("input[name='form_token']")["value"]
    assert_no_enqueued_emails do
      post sign_in_path, params: { email: "quick@example.com", newsletter_opt_in: "1", form_token: token }
    end
    assert_response :unprocessable_content
    assert_select ".alert", text: /Please wait a moment/
    assert_select "input[name='email'][value='quick@example.com']"
    assert_select "input[name='newsletter_opt_in'][checked]"

    fresh_token = html_document.at_css("input[name='form_token']")["value"]
    travel 3.seconds
    assert_enqueued_emails 2 do
      post sign_in_path, params: { email: "quick@example.com", newsletter_opt_in: "1", form_token: fresh_token }
    end
    assert_redirected_to check_email_path
  end

  test "form tokens cannot be forged transferred to another session or used after expiry" do
    form = sign_in_params(email: "forged@example.com")
    assert_no_difference "User.count" do
      assert_no_enqueued_emails do
        post sign_in_path, params: form.merge(form_token: "#{form[:form_token]}tampered")
        assert_response :unprocessable_content

        other_browser = open_session
        other_browser.post sign_in_path, params: form
        assert_equal 422, other_browser.response.status

        travel 2.hours
        post sign_in_path, params: form
        assert_response :unprocessable_content
      end
    end
  end

  test "honeypot traffic cannot spend another person's email quota" do
    assert_no_enqueued_emails do
      6.times do
        post sign_in_path, params: { email: "target@example.com", website: "spam" }
        assert_redirected_to check_email_path
      end
    end

    assert_enqueued_emails 1 do
      post sign_in_path, params: sign_in_params(email: "target@example.com")
    end
    assert_redirected_to check_email_path
  end

  test "Turnstile rejects new and returning requests before either email is queued" do
    returning = User.create!(email: "returning@example.com", verified_at: Time.current, enrollment_status: "inactive")
    with_turnstile_response(success: false, "error-codes": [ "timeout-or-duplicate" ]) do
      [ "bot@example.com", returning.email ].each do |email|
        assert_no_difference "User.count" do
          assert_no_enqueued_emails do
            post sign_in_path, params: sign_in_params(email: email, newsletter_opt_in: "1", "cf-turnstile-response": "invalid-token")
          end
        end
        assert_response :unprocessable_content
        assert_select ".alert", text: /browser verification/
      end
    end
    assert_nil returning.reload.newsletter_requested_at

    with_turnstile_response(success: true, hostname: "www.example.com", action: "sign_in") do
      assert_enqueued_emails 1 do
        post sign_in_path, params: sign_in_params(email: "human@example.com", "cf-turnstile-response": "valid-token")
      end
      assert_redirected_to check_email_path
    end
  end

  test "unavailable browser verification fails closed with a retry message" do
    with_turnstile_response(success: false, "error-codes": [ "internal-error" ]) do
      assert_no_difference "User.count" do
        assert_no_enqueued_emails do
          post sign_in_path, params: sign_in_params(email: "outage@example.com", "cf-turnstile-response": "token")
        end
      end
      assert_response :service_unavailable
      assert_equal "30", response.headers["Retry-After"]
      assert_select ".alert", text: /temporarily unavailable/
      assert_select "input[name='email'][value='outage@example.com']"
    end
  end

  test "rejected challenges cannot spend another person's email quota" do
    with_turnstile_response(success: false) do
      6.times do
        assert_no_enqueued_emails do
          post sign_in_path, params: sign_in_params(email: "target@example.com", "cf-turnstile-response": "invalid")
        end
        assert_response :unprocessable_content
      end
    end

    with_turnstile_response(success: true, hostname: "www.example.com", action: "sign_in") do
      assert_enqueued_emails 1 do
        post sign_in_path, params: sign_in_params(email: "target@example.com", "cf-turnstile-response": "valid")
      end
      assert_redirected_to check_email_path
    end
  end

  test "a new email verifies without entering the waitlist before the readiness check" do
    assert_emails 1 do
      post sign_in_path, params: sign_in_params(email: "new@example.com")
    end

    user = User.find_by!(email: "new@example.com")
    assert_nil user.newsletter_requested_at
    assert_redirected_to check_email_path

    token = user.generate_token_for(:email_verification)
    get verify_email_path(token: token)

    assert_response :success
    assert_equal "no-store", response.headers["Cache-Control"]
    assert_equal "same-origin", response.headers["Referrer-Policy"]
    assert_not user.reload.verified?
    assert_select "form[action='#{verify_email_path}']"

    post verify_email_path, params: { token: token }

    assert_redirected_to dashboard_path
    assert_equal "inactive", user.reload.enrollment_status
    follow_redirect!
    assert_equal "no-store", response.headers["Cache-Control"]
    assert_select "h1", /Your account is ready/
    assert_select ".dashboard-next-steps" do
      assert_select "li", text: /Get on the waitlist/
      assert_select "a[href='#{edit_profile_path}']", text: /Make your profile public/
      assert_select "li.is-complete", count: 0
      assert_select "li:not(.is-complete)", count: 2
    end
    assert_select "input[name='readiness[]']", count: 6
    assert_select "[data-waitlist-readiness] [data-readiness-checklist-target='activation'][hidden]"
    assert_select "a", "Sign out"

    post verify_email_path, params: { token: token }
    assert_redirected_to sign_in_path
  end

  test "sign-in requests are throttled per email address" do
    5.times do
      post sign_in_path, params: sign_in_params(email: "target@example.com")
      assert_redirected_to check_email_path
    end

    post sign_in_path, params: sign_in_params(email: " TARGET@example.com ")

    assert_response :too_many_requests
  end

  test "the daily email limit prevents sustained mail abuse and expires" do
    10.times do
      assert_enqueued_emails 1 do
        post sign_in_path, params: sign_in_params(email: "daily@example.com")
      end
      travel 16.minutes
    end

    assert_no_enqueued_emails do
      post sign_in_path, params: sign_in_params(email: " DAILY@example.com ")
    end
    assert_response :too_many_requests
    assert_equal "86400", response.headers["Retry-After"]

    travel 1.day
    assert_enqueued_emails 1 do
      post sign_in_path, params: sign_in_params(email: "daily@example.com")
    end
    assert_redirected_to check_email_path
  end

  test "IP limits stop bursts and sustained requests even when emails rotate" do
    assert_no_difference "User.count" do
      assert_no_enqueued_emails do
        3.times do |burst|
          20.times do |index|
            post sign_in_path, params: { email: "bot#{index}@example.com", website: "spam" }
            assert_redirected_to check_email_path
          end
          if burst.zero?
            post sign_in_path, params: { email: "burst@example.com", website: "spam" }
            assert_response :too_many_requests
            assert_equal "300", response.headers["Retry-After"]
          end
          travel 6.minutes
        end

        post sign_in_path, params: { email: "sustained@example.com", website: "spam" }
        assert_response :too_many_requests
        assert_equal "3600", response.headers["Retry-After"]
      end
    end
  end

  test "repeated submissions send one pair of emails and preserve the original sign-in link" do
    assert_enqueued_emails 2 do
      post sign_in_path, params: sign_in_params(email: "repeat@example.com", newsletter_opt_in: "1")
    end
    user = User.find_by!(email: "repeat@example.com")
    token = user.generate_token_for(:email_verification)
    newsletter_token = user.generate_token_for(:newsletter_confirmation)

    assert_no_enqueued_emails do
      post sign_in_path, params: sign_in_params(email: " REPEAT@example.com ", newsletter_opt_in: "1")
    end
    assert_redirected_to check_email_path

    post verify_email_path, params: { token: token }
    assert_redirected_to dashboard_path
    post confirm_newsletter_path, params: { token: newsletter_token }
    assert user.reload.newsletter_confirmed_at
  end

  test "requesting another sign-in link does not repeatedly send newsletter confirmations" do
    post sign_in_path, params: sign_in_params(email: "newsletter@example.com", newsletter_opt_in: "1")
    user = User.find_by!(email: "newsletter@example.com")
    sign_in_token = user.generate_token_for(:email_verification)
    newsletter_token = user.generate_token_for(:newsletter_confirmation)
    travel 2.minutes

    assert_enqueued_emails 1 do
      post sign_in_path, params: sign_in_params(email: user.email, newsletter_opt_in: "1")
    end

    post verify_email_path, params: { token: sign_in_token }
    assert_redirected_to sign_in_path
    post confirm_newsletter_path, params: { token: newsletter_token }
    assert user.reload.newsletter_confirmed_at
  end

  test "malformed email addresses show a correction before either confirmation is queued" do
    assert_no_enqueued_emails do
      post sign_in_path, params: sign_in_params(email: "builder..name@example.com", newsletter_opt_in: "1")
    end

    assert_response :unprocessable_content
    assert_select ".alert", text: "Email is invalid"
    assert_select "input[name='email'][value='builder..name@example.com']"
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

  test "a verification link can be retried when the enrollment update rolls back" do
    user = User.create!(email: "retry@example.com")
    token = user.generate_token_for(:email_verification)
    user.update_column(:name, "x" * 101)

    post verify_email_path, params: { token: token }
    assert_response :unprocessable_content
    assert_not user.reload.verified?

    user.update_column(:name, nil)
    post verify_email_path, params: { token: token }
    assert_redirected_to dashboard_path
    assert user.reload.verified?
  end

  test "malformed magic-link tokens fail cleanly without starting a session" do
    [ nil, [], { forged: "token" }, "x" * 2049 ].each do |token|
      get verify_email_path, params: { token: token }
      assert_redirected_to sign_in_path
      post verify_email_path, params: { token: token }
      assert_redirected_to sign_in_path
      get confirm_newsletter_path, params: { token: token }
      assert_redirected_to root_path
      post confirm_newsletter_path, params: { token: token }
      assert_redirected_to root_path
    end
    get dashboard_path
    assert_redirected_to sign_in_path
  end

  test "newsletter consent sends a separate confirmation and does not subscribe immediately" do
    assert_emails 2 do
      post sign_in_path, params: sign_in_params(email: "reader@example.com", newsletter_opt_in: "1")
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
    post sign_in_path, params: sign_in_params(email: user.email)

    token = user.reload.generate_token_for(:email_verification)
    get verify_email_path(token: token)
    post verify_email_path, params: { token: token }

    assert_equal "offered", user.reload.enrollment_status
    follow_redirect!
    assert_select "h1", /Your seat is ready/
    assert_select ".dashboard-next-steps li", text: /Become an Active Builder/
    assert_select ".dashboard-next-steps li.is-complete", count: 0
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

  private

  def with_turnstile_response(**body)
    previous_configuration = Rails.configuration.x.turnstile
    Rails.configuration.x.turnstile = ActiveSupport::OrderedOptions.new
    Rails.configuration.x.turnstile.enabled = true
    Rails.configuration.x.turnstile.site_key = "test-site-key"
    Rails.configuration.x.turnstile.secret_key = "test-secret-key"
    Rails.configuration.x.turnstile.hostnames = [ "www.example.com" ]
    transport = Object.new
    transport.define_singleton_method(:request) { |_request| Struct.new(:code, :body).new("200", body.to_json) }
    with_stubbed_singleton_method(Net::HTTP, :start, ->(*_args, **_options, &block) { block.call(transport) }) { yield }
  ensure
    Rails.configuration.x.turnstile = previous_configuration
  end
end
