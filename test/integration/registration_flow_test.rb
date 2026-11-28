require "test_helper"

class RegistrationFlowTest < ActionDispatch::IntegrationTest
  setup do
    @program = Program.create!(name: "Continuous", starts_on: Date.new(2026, 8, 20), ends_on: Date.new(2026, 12, 17), capacity: 10)
  end

  test "Turnstile rejects new and returning requests before either email is queued" do
    returning = User.create!(email: "returning@example.com", verified_at: Time.current, enrollment_status: "inactive")
    with_turnstile_response(success: false, "error-codes": [ "timeout-or-duplicate" ]) do
      [ "bot@example.com", returning.email ].each do |email|
        assert_no_difference "User.count" do
          assert_no_enqueued_emails do
            post join_path, params: sign_in_params(path: join_path, email: email, newsletter_opt_in: "1", "cf-turnstile-response": "invalid-token")
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
