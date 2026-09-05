posthog_token = ENV["POSTHOG_PROJECT_TOKEN"].presence
posthog_host = "https://eu.i.posthog.com"

Rails.application.config.x.posthog.enabled = posthog_token.present? && !Rails.env.test?
Rails.application.config.x.posthog.token = posthog_token
Rails.application.config.x.posthog.host = posthog_host
Rails.application.config.x.posthog.client = if Rails.application.config.x.posthog.enabled
  PostHog::Client.new(
    api_key: posthog_token,
    host: posthog_host,
    on_error: ->(_status, error) { Rails.logger.warn("PostHog delivery failed (#{error.class})") }
  )
end

at_exit { Rails.configuration.x.posthog.client&.shutdown(timeout: 2) }
