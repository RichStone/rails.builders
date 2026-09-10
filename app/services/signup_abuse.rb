class SignupAbuse
  REASONS = %i[
    honeypot invalid_form too_fast turnstile_rejected turnstile_unavailable
    ip_rate_limit email_rate_limit mail_cooldown registration_created
    verification_link_requested registration_verified sign_in_completed invalid_verification
    email_bounced email_complained email_suppressed email_failed
  ].freeze
  ALERT_THRESHOLDS = {
    registration_created: 20, honeypot: 20, invalid_form: 20, too_fast: 20,
    turnstile_rejected: 20, turnstile_unavailable: 3, ip_rate_limit: 20,
    email_rate_limit: 20, invalid_verification: 20, email_bounced: 3,
    email_complained: 1, email_suppressed: 3, email_failed: 3
  }.freeze

  def self.record(reason)
    return false unless reason.is_a?(Symbol) || reason.is_a?(String)
    return false unless REASONS.any? { |allowed| allowed.to_s == reason.to_s }

    reason = reason.to_sym
    hour = Time.current.beginning_of_hour
    count = Rails.cache.increment(key(reason, hour), 1, expires_in: 48.hours)
    return false unless count

    threshold = ALERT_THRESHOLDS[reason]
    if threshold && count >= threshold && Rails.cache.write("#{key(reason, hour)}:alerted", true, expires_in: 48.hours, unless_exist: true)
      notify(reason, count)
    end
    true
  rescue StandardError => error
    Rails.logger.warn("Signup monitoring failed (#{error.class})")
    false
  end

  def self.counts
    hour = Time.current.beginning_of_hour
    keys = REASONS.to_h { |reason| [ reason, 24.times.map { |offset| key(reason, hour - offset.hours) } ] }
    values = Rails.cache.read_multi(*keys.values.flatten)
    keys.transform_values { |bucket_keys| bucket_keys.sum { |bucket_key| values[bucket_key].to_i } }
  rescue StandardError => error
    Rails.logger.warn("Signup monitoring unavailable (#{error.class})")
    nil
  end

  def self.key(reason, hour)
    "signup-abuse:#{hour.to_i}:#{reason}"
  end

  def self.notify(reason, count)
    Honeybadger.notify(
      error_class: "SignupAbuseSpike", error_message: "Signup monitoring: #{reason}", cause: nil,
      fingerprint: "signup-abuse:#{reason}",
      context: { reason: reason.to_s, count: count, window: "hour" },
      rack_env: {}, global_context: {}, breadcrumbs: [], request_id: "",
      parameters: {}, session: {}, cgi_data: {}
    )
  rescue StandardError => error
    Rails.logger.warn("Signup alert unavailable (#{error.class})")
  end
  private_class_method :key, :notify
end
