require "test_helper"

class ClickfunnelsNewsletterJobTest < ActiveJob::TestCase
  test "does nothing until both confirmations exist" do
    user = User.create!(email: "reader@example.com", newsletter_confirmed_at: Time.current)

    ClickfunnelsNewsletterJob.perform_now(user.id)

    assert_equal "not_requested", user.reload.clickfunnels_sync_status
  end

  test "records a visible no-op locally even when a token is present" do
    user = User.create!(email: "reader@example.com", verified_at: Time.current, newsletter_confirmed_at: Time.current)
    original_token = ENV["CLICKFUNNELS_API_TOKEN"]
    original_start = Net::HTTP.method(:start)
    ENV["CLICKFUNNELS_API_TOKEN"] = "must-not-be-used"
    Net::HTTP.define_singleton_method(:start) { |*| raise "test must not make a ClickFunnels request" }

    ClickfunnelsNewsletterJob.perform_now(user.id)

    assert_equal "skipped_local", user.reload.clickfunnels_sync_status
  ensure
    Net::HTTP.define_singleton_method(:start, original_start) if original_start
    original_token ? ENV["CLICKFUNNELS_API_TOKEN"] = original_token : ENV.delete("CLICKFUNNELS_API_TOKEN")
  end
end
