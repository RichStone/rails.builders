require "test_helper"
require "open3"

class RailsBuildersConfigurationTest < ActiveSupport::TestCase
  test "validated OG seed addresses are available through Rails configuration" do
    assert_equal [ "facilitator@example.com", "og-builder@example.com" ], Rails.configuration.x.rails_builders.og_emails
    assert_equal "facilitator@example.com", Rails.configuration.x.rails_builders.facilitator_email
  end
  test "error reports exclude request URLs and sessions" do
    assert Honeybadger.config[:"request.disable_url"]
    assert Honeybadger.config[:"request.disable_session"]
  end

  test "application startup rejects malformed private seed addresses" do
    _output, errors, status = Open3.capture3(
      {
        "RAILS_ENV" => "test",
        "RAILS_BUILDERS_OG_EMAILS" => "not-an-address",
        "RAILS_BUILDERS_FACILITATOR_EMAIL" => ""
      },
      Rails.root.join("bin/rails").to_s,
      "runner",
      "true"
    )

    assert_not status.success?
    assert_includes errors, "RAILS_BUILDERS_OG_EMAILS contains invalid addresses"
  end
end
