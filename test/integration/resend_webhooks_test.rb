require "test_helper"

class ResendWebhooksTest < ActionDispatch::IntegrationTest
  setup do
    @previous_secret = ENV["RESEND_WEBHOOK_SECRET"]
    ENV["RESEND_WEBHOOK_SECRET"] = "whsec_#{Base64.strict_encode64('test-webhook-key')}"
  end

  teardown do
    ENV["RESEND_WEBHOOK_SECRET"] = @previous_secret
  end

  test "signed bounce events are counted once without logging recipient or subject" do
    payload = { type: "email.bounced", data: { from: "Rails Builders <hello@rails.builders>", to: [ "private@example.com" ], subject: "Private email subject" } }.to_json
    logs = StringIO.new
    original_logger = Rails.logger
    Rails.logger = ActiveSupport::Logger.new(logs)

    2.times do
      post "/webhooks/resend", params: payload, headers: signed_headers(payload)
      assert_response :no_content
    end

    assert_equal 1, SignupAbuse.counts.fetch(:email_bounced)
    assert_not_includes logs.string, "private@example.com"
    assert_not_includes logs.string, "Private email subject"
  ensure
    Rails.logger = original_logger
  end

  test "forged stale malformed and oversized events cannot affect counts" do
    payload = { type: "email.complained", data: { from: "hello@rails.builders" } }.to_json
    headers = signed_headers(payload)
    post "/webhooks/resend", params: payload.sub("complained", "bounced"), headers: headers
    assert_response :bad_request

    post "/webhooks/resend", params: payload, headers: signed_headers(payload, timestamp: 6.minutes.ago.to_i)
    assert_response :bad_request

    post "/webhooks/resend", params: payload, headers: signed_headers(payload, timestamp: 6.minutes.from_now.to_i)
    assert_response :bad_request

    post "/webhooks/resend", params: "{", headers: signed_headers("{")
    assert_response :bad_request

    post "/webhooks/resend", params: payload, headers: { "CONTENT_TYPE" => "application/json" }
    assert_response :bad_request

    huge_payload = "x" * (64.kilobytes + 1)
    post "/webhooks/resend", params: huge_payload, headers: signed_headers(huge_payload)
    assert_response :content_too_large
    assert_equal 0, SignupAbuse.counts.values.sum
  end

  test "unrelated senders and unrequested events are acknowledged without counting" do
    [ [ "email.bounced", "hello@other.example" ], [ "email.opened", "hello@rails.builders" ] ].each do |type, from|
      payload = { type: type, data: { from: from } }.to_json
      post "/webhooks/resend", params: payload, headers: signed_headers(payload)
      assert_response :no_content
    end
    assert_equal 0, SignupAbuse.counts.values.sum
  end

  test "missing secret refuses processing and cache outages invite a retry" do
    payload = { type: "email.bounced", data: { from: "hello@rails.builders" } }.to_json
    ENV.delete("RESEND_WEBHOOK_SECRET")
    post "/webhooks/resend", params: payload, headers: signed_headers(payload)
    assert_response :service_unavailable

    ENV["RESEND_WEBHOOK_SECRET"] = "whsec_#{Base64.strict_encode64('test-webhook-key')}"
    with_stubbed_singleton_method(Rails.cache, :write, ->(*) { raise IOError }) do
      post "/webhooks/resend", params: payload, headers: signed_headers(payload)
      assert_response :service_unavailable
    end
  end

  test "chunked bodies are bounded before reading or parsing the complete payload" do
    reads = []
    stream = StringIO.new("x" * 128.kilobytes)
    stream.define_singleton_method(:read) do |length = nil, *arguments|
      reads << length
      super(length, *arguments)
    end

    post "/webhooks/resend", headers: { "CONTENT_TYPE" => "application/json" }, env: {
      "rack.input" => stream, "HTTP_TRANSFER_ENCODING" => "chunked", "CONTENT_LENGTH" => ""
    }

    assert_response :content_too_large
    assert_equal [ 65_537 ], reads
    assert_equal 0, SignupAbuse.counts.values.sum
  end

  private

  def signed_headers(payload, timestamp: Time.now.to_i, id: "msg_test_123")
    digest = OpenSSL::HMAC.digest("SHA256", "test-webhook-key", "#{id}.#{timestamp}.#{payload}")
    {
      "CONTENT_TYPE" => "application/json",
      "svix-id" => id,
      "svix-timestamp" => timestamp.to_s,
      "svix-signature" => "v1,#{Base64.strict_encode64(digest)}"
    }
  end
end
