ENV["RAILS_ENV"] ||= "test"
require_relative "../../config/environment"
require "minitest/autorun"
require "net/http"
require "open3"

class TurnstileTest < Minitest::Test
  Response = Data.define(:code, :body)

  def setup
    @configuration = Rails.configuration.x.turnstile
    Rails.configuration.x.turnstile = ActiveSupport::OrderedOptions.new
    Rails.configuration.x.turnstile.enabled = true
    Rails.configuration.x.turnstile.site_key = "test-site-key"
    Rails.configuration.x.turnstile.secret_key = "test-secret-key"
    Rails.configuration.x.turnstile.hostnames = [ "rails.builders" ]
  end

  def teardown
    Rails.configuration.x.turnstile = @configuration
  end

  def test_verifies_the_sign_in_challenge_with_cloudflare_without_sending_personal_data
    with_siteverify(Response.new("200", { success: true, hostname: "rails.builders", action: "sign_in" }.to_json)) do |requests|
      assert_equal :verified, Turnstile.verify(token: "challenge-token", hostname: "rails.builders")
      assert_equal "/turnstile/v0/siteverify", requests.first.path
      assert_equal "POST", requests.first.method
      assert_equal({ "secret" => "test-secret-key", "response" => "challenge-token" }, URI.decode_www_form(requests.first.body).to_h)
    end
  end

  def test_rejects_forged_mismatched_and_replayed_challenges
    [
      { success: true, hostname: "other.example", action: "sign_in" },
      { success: true, hostname: "rails.builders", action: "other_action" },
      { success: true, hostname: "rails.builders" },
      { success: "true", hostname: "rails.builders", action: "sign_in" },
      { success: false, "error-codes": [ "timeout-or-duplicate" ] }
    ].each do |result|
      with_siteverify(Response.new("200", result.to_json)) do
        refute_equal :verified, Turnstile.verify(token: "challenge-token", hostname: "rails.builders")
      end
    end

    with_siteverify(Response.new("200", { success: true, hostname: "other.example", action: "sign_in" }.to_json)) do |requests|
      assert_equal :rejected, Turnstile.verify(token: "challenge-token", hostname: "other.example")
      assert_empty requests
    end
  end

  def test_rejects_missing_structured_blank_and_oversized_tokens_without_a_network_request
    with_siteverify(Response.new("200", "{}")) do |requests|
      [ nil, "", "  ", [], { token: "forged" }, "t" * 2049 ].each do |token|
        assert_equal :rejected, Turnstile.verify(token: token, hostname: "rails.builders")
      end
      assert_empty requests
    end
  end

  def test_provider_outages_and_malformed_responses_are_unavailable_instead_of_bypassing_verification
    [
      Response.new("503", '{"success":true}'), Response.new("302", "{}"),
      Response.new("200", "<html>upstream error</html>"), Response.new("200", "null"),
      Response.new("200", "[]"), Response.new("200", "{}"),
      Response.new("200", '{"success":false,"error-codes":["internal-error"]}'),
      Response.new("200", '{"success":false,"error-codes":["invalid-input-secret"]}'),
      Net::ReadTimeout.new, SocketError.new, OpenSSL::SSL::SSLError.new
    ].each do |response|
      with_siteverify(response) do
        assert_equal :unavailable, Turnstile.verify(token: "challenge-token", hostname: "rails.builders")
      end
    end
  end

  def test_default_development_and_test_configuration_does_not_call_cloudflare
    Rails.configuration.x.turnstile.enabled = false
    with_siteverify(Response.new("200", "{}")) do |requests|
      assert_equal :verified, Turnstile.verify(token: nil, hostname: "localhost")
      assert_empty requests
    end
  end

  def test_enabled_verification_with_missing_keys_cannot_silently_allow_sign_in
    Rails.configuration.x.turnstile.secret_key = nil
    with_siteverify(Response.new("200", "{}")) do |requests|
      assert_equal :unavailable, Turnstile.verify(token: "challenge-token", hostname: "rails.builders")
      assert_empty requests
    end
  end

  def test_production_boot_requires_keys_but_asset_builds_do_not
    environment = {
      "RAILS_ENV" => "production", "SECRET_KEY_BASE" => "test-secret-key-base",
      "SECRET_KEY_BASE_DUMMY" => nil, "TURNSTILE_SITE_KEY" => nil, "TURNSTILE_SECRET_KEY" => nil,
      "HONEYBADGER_API_KEY" => nil, "POSTHOG_PROJECT_TOKEN" => nil
    }
    _output, errors, status = Open3.capture3(environment, Rails.root.join("bin/rails").to_s, "runner", "true")
    refute status.success?
    assert_includes errors, "TURNSTILE_SITE_KEY and TURNSTILE_SECRET_KEY are required in production"

    _output, errors, status = Open3.capture3(environment.merge("SECRET_KEY_BASE_DUMMY" => "1"), Rails.root.join("bin/rails").to_s, "runner", "true")
    assert status.success?, errors
  end

  def test_production_rejects_cloudflare_test_keys
    environment = {
      "RAILS_ENV" => "production", "SECRET_KEY_BASE" => "test-secret-key-base",
      "SECRET_KEY_BASE_DUMMY" => nil, "HONEYBADGER_API_KEY" => nil, "POSTHOG_PROJECT_TOKEN" => nil
    }
    [
      { "TURNSTILE_SITE_KEY" => "1x00000000000000000000AA", "TURNSTILE_SECRET_KEY" => "production-secret" },
      { "TURNSTILE_SITE_KEY" => "production-site", "TURNSTILE_SECRET_KEY" => "1x0000000000000000000000000000000AA" }
    ].each do |keys|
      _output, errors, status = Open3.capture3(environment.merge(keys), Rails.root.join("bin/rails").to_s, "runner", "true")
      refute status.success?
      assert_includes errors, "Turnstile test keys cannot be used in production"
    end
  end

  private

  def with_siteverify(response)
    requests = []
    transport = Object.new
    transport.define_singleton_method(:request) do |request|
      requests << request
      raise response if response.is_a?(Exception)
      response
    end
    original = Net::HTTP.method(:start)
    Net::HTTP.define_singleton_method(:start) do |hostname, port, **options, &block|
      raise "Unexpected verification destination" unless hostname == "challenges.cloudflare.com" && port == 443 && options[:use_ssl]
      raise "Verification must have bounded timeouts without automatic retries" unless options.values_at(:open_timeout, :read_timeout, :write_timeout, :max_retries) == [ 2, 3, 3, 0 ]
      block.call(transport)
    end
    yield requests
  ensure
    Net::HTTP.define_singleton_method(:start, original)
  end
end
