site_key = ENV["TURNSTILE_SITE_KEY"].presence
secret_key = ENV["TURNSTILE_SECRET_KEY"].presence

if Rails.env.production? && !ENV["SECRET_KEY_BASE_DUMMY"] && !(site_key && secret_key)
  raise ArgumentError, "TURNSTILE_SITE_KEY and TURNSTILE_SECRET_KEY are required in production"
end

test_keys = %w[
  1x00000000000000000000AA 2x00000000000000000000AB 1x00000000000000000000BB
  2x00000000000000000000BB 3x00000000000000000000FF
  1x0000000000000000000000000000000AA 2x0000000000000000000000000000000AA 3x0000000000000000000000000000000AA
]
if Rails.env.production? && (test_keys & [ site_key, secret_key ]).any?
  raise ArgumentError, "Turnstile test keys cannot be used in production"
end

Rails.application.config.x.turnstile.enabled = !Rails.env.test? && (Rails.env.production? || (site_key.present? && secret_key.present?))
Rails.application.config.x.turnstile.site_key = site_key
Rails.application.config.x.turnstile.secret_key = secret_key
app_host = ENV.fetch("APP_HOST", "rails.builders")
Rails.application.config.x.turnstile.hostnames = [ app_host, "www.#{app_host}" ].uniq.freeze
