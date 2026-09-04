require "test_helper"
require "json"
require "open3"

class RailsBuildersConfigurationTest < ActiveSupport::TestCase
  test "validated OG seed addresses are available through Rails configuration" do
    output, errors, status = Open3.capture3(
      {
        "RAILS_ENV" => "test",
        "RAILS_BUILDERS_OG_EMAILS" => "facilitator@example.com,og-builder@example.com",
        "RAILS_BUILDERS_FACILITATOR_EMAIL" => "facilitator@example.com"
      },
      Rails.root.join("bin/rails").to_s,
      "runner",
      "puts({ og_emails: Rails.configuration.x.rails_builders.og_emails, facilitator_email: Rails.configuration.x.rails_builders.facilitator_email }.to_json)"
    )

    assert status.success?, errors
    configuration = JSON.parse(output.lines.last)
    assert_equal [ "facilitator@example.com", "og-builder@example.com" ], configuration.fetch("og_emails")
    assert_equal "facilitator@example.com", configuration.fetch("facilitator_email")
  end
  test "error reports exclude request URLs and sessions" do
    assert Honeybadger.config[:"request.disable_url"]
    assert Honeybadger.config[:"request.disable_session"]
  end

  test "CSRF rejections are reported instead of silently ignored" do
    # Honeybadger ignores these by default, which is how a bug that rejected
    # every non-Turbo form POST stayed invisible in production.
    ignored = Honeybadger.config.ignored_classes
    assert_not_includes ignored, "ActionController::InvalidAuthenticityToken"
    assert_includes ignored, "ActionController::RoutingError", "the rest of the gem defaults must stay ignored"
  end

  test "Google API clients do not log authenticated HTTP details" do
    assert_not Google::Apis.logger.debug?
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
