class ProductAnalytics
  EVENTS = %w[
    membership_started
    registration_created
    registration_verified
    seat_offer_received
    sign_in_completed
    verification_link_requested
    waitlist_joined
  ].freeze

  def self.capture(event)
    return false unless EVENTS.include?(event)

    client = Rails.configuration.x.posthog.client
    return false unless client&.enabled?

    # Omitting distinct_id makes posthog-ruby generate a fresh personless ID
    # and attach $process_person_profile=false.
    !!client.capture({ event:, properties: {} })
  rescue StandardError => error
    Rails.logger.warn("PostHog capture failed (#{error.class})")
    false
  end
end
