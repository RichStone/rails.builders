require "test_helper"

class ProductAnalyticsIntegrationTest < ActionDispatch::IntegrationTest
  setup do
    @previous_config = Rails.configuration.x.posthog.to_h
    Rails.configuration.x.posthog.enabled = true
    Rails.configuration.x.posthog.token = "phc_test_public_token"
    Rails.configuration.x.posthog.host = "https://eu.i.posthog.com"
    @program = Program.create!(name: "Continuous", starts_on: Date.new(2026, 8, 20), ends_on: Date.new(2026, 12, 17), capacity: 10)
  end

  teardown do
    @previous_config.each { |key, value| Rails.configuration.x.posthog.public_send("#{key}=", value) }
  end

  test "public pages expose only the allowlisted route and CTA contract" do
    get root_path

    assert_response :success
    assert_select "body[data-posthog-token='phc_test_public_token'][data-posthog-host='https://eu.i.posthog.com'][data-posthog-route='home'][data-posthog-path='/']"
    assert_select "[data-analytics-placement]", count: 5
    assert_equal %w[footer format header hero readiness], css_select("[data-analytics-placement]").map { |node| node["data-analytics-placement"] }.sort
    assert_includes response.headers.fetch("Content-Security-Policy"), "connect-src 'self' https://eu.i.posthog.com"
  end

  test "token-bearing verification pages are excluded and the signed-in dashboard remains anonymous" do
    user = User.create!(email: "builder@example.com")
    token = user.generate_token_for(:email_verification)

    get verify_email_path(token:)
    assert_response :success
    assert_select "body[data-posthog-token]", count: 0
    assert_not_includes response.body, "phc_test_public_token"

    post verify_email_path, params: { token: }
    assert_redirected_to dashboard_path
    follow_redirect!

    assert_select "body[data-posthog-route='dashboard'][data-posthog-path='/dashboard']"
    assert_select "body[data-posthog-user-id]", count: 0
    assert_not_includes response.body, user.email
  end

  test "registration and sign-in outcomes are emitted only after success" do
    captured = []
    replacement = ->(event) { captured << event; true }

    with_stubbed_singleton_method(ProductAnalytics, :capture, replacement) do
      post sign_in_path, params: { email: "new@example.com" }
      user = User.find_by!(email: "new@example.com")
      post verify_email_path, params: { token: user.generate_token_for(:email_verification) }

      post sign_in_path, params: { email: "new@example.com" }
      post verify_email_path, params: { token: user.reload.generate_token_for(:email_verification) }

      post sign_in_path, params: { email: "not-an-email" }
    end

    assert_equal %w[registration_created registration_verified verification_link_requested sign_in_completed], captured
    assert_not_includes captured.to_s, "new@example.com"
  end
end
