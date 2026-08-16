require "test_helper"

class ClickfunnelsNewsletterJobTest < ActiveJob::TestCase
  test "does nothing until both confirmations exist" do
    user = User.create!(email: "reader@example.com", newsletter_confirmed_at: Time.current)

    ClickfunnelsNewsletterJob.perform_now(user.id)

    assert_equal "not_requested", user.reload.clickfunnels_sync_status
  end

  test "reports missing local configuration without breaking registration" do
    user = User.create!(email: "reader@example.com", verified_at: Time.current, newsletter_confirmed_at: Time.current)
    original_token = ENV.delete("CLICKFUNNELS_API_TOKEN")

    ClickfunnelsNewsletterJob.perform_now(user.id)

    assert_equal "missing_configuration", user.reload.clickfunnels_sync_status
  ensure
    ENV["CLICKFUNNELS_API_TOKEN"] = original_token if original_token
  end
end
