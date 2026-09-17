class ResendWebhooksController < ActionController::Metal
  include ActionController::Head

  EVENTS = {
    "email.bounced" => :email_bounced,
    "email.complained" => :email_complained,
    "email.suppressed" => :email_suppressed,
    "email.failed" => :email_failed
  }.freeze

  # Keep callbacks for messages sent before the display name changed.
  SENDERS = [
    "hello@rails.builders",
    "Rails Builders <hello@rails.builders>",
    "Rails.Builders <hello@rails.builders>",
    '"Rails.Builders" <hello@rails.builders>'
  ].freeze

  def create
    secret = ENV["RESEND_WEBHOOK_SECRET"]
    return head(:service_unavailable) if secret.blank?
    return head(:content_too_large) if request.get_header("CONTENT_LENGTH").to_i > 64.kilobytes

    # Metal avoids automatic JSON parsing/logging of recipients and subjects.
    payload = request.body.read(64.kilobytes + 1)
    return head(:content_too_large) if payload.bytesize > 64.kilobytes

    event = verified_event(payload, secret)
    return head(:bad_request) unless event

    reason = EVENTS[event["type"]]
    sender = event["data"].is_a?(Hash) && event["data"]["from"]
    return head(:no_content) unless reason && SENDERS.include?(sender)

    event_key = "resend-webhook:#{Digest::SHA256.hexdigest(request.headers['svix-id'])}"
    unless Rails.cache.write(event_key, true, expires_in: 72.hours, unless_exist: true)
      return head(Rails.cache.read(event_key) ? :no_content : :service_unavailable)
    end

    unless SignupAbuse.record(reason)
      Rails.cache.delete(event_key)
      return head(:service_unavailable)
    end

    head :no_content
  rescue StandardError => error
    Rails.logger.warn("Email monitoring unavailable (#{error.class})")
    head :service_unavailable
  end

  private

  def verified_event(payload, secret)
    signatures = request.headers["svix-signature"].to_s.split.select { |signature| signature.start_with?("v1,") }.join(" ")
    Resend::Webhooks.verify(
      payload: payload, webhook_secret: secret,
      headers: {
        svix_id: request.headers["svix-id"],
        svix_timestamp: request.headers["svix-timestamp"],
        svix_signature: signatures
      }
    )
    event = JSON.parse(payload)
    event if event.is_a?(Hash)
  rescue RuntimeError, JSON::ParserError
    nil
  end
end
