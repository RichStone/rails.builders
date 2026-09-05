require "test_helper"

class ProductAnalyticsTest < ActiveSupport::TestCase
  setup do
    @previous_client = Rails.configuration.x.posthog.client
  end

  teardown do
    Rails.configuration.x.posthog.client = @previous_client
  end

  test "capture sends only the explicit event contract without account linking" do
    captured = nil
    client = Object.new
    client.define_singleton_method(:capture) { |payload| captured = payload }
    client.define_singleton_method(:enabled?) { true }
    Rails.configuration.x.posthog.client = client

    assert ProductAnalytics.capture("registration_created")

    assert_not captured.key?(:distinct_id)
    assert_equal "registration_created", captured.fetch(:event)
    assert_empty captured.fetch(:properties)
  end

  test "capture failures never break the product flow" do
    client = Object.new
    client.define_singleton_method(:capture) { |_payload| raise IOError, "offline" }
    client.define_singleton_method(:enabled?) { true }
    Rails.configuration.x.posthog.client = client

    assert_not ProductAnalytics.capture("registration_created")
  end

  test "capture rejects events outside the measurement contract" do
    assert_not ProductAnalytics.capture("user_17_clicked_secret_button")
  end
end
