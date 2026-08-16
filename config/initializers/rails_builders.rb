require "uri"

og_emails = ENV.fetch("RAILS_BUILDERS_OG_EMAILS", "").split(",").map { |email| email.strip.downcase }.reject(&:empty?).uniq
invalid_email_count = og_emails.count { |email| email.length > 320 || !email.match?(URI::MailTo::EMAIL_REGEXP) }
raise ArgumentError, "RAILS_BUILDERS_OG_EMAILS contains invalid addresses" if invalid_email_count.positive?

facilitator_email = ENV.fetch("RAILS_BUILDERS_FACILITATOR_EMAIL", "").strip.downcase.presence
if facilitator_email && (facilitator_email.length > 320 || !facilitator_email.match?(URI::MailTo::EMAIL_REGEXP))
  raise ArgumentError, "RAILS_BUILDERS_FACILITATOR_EMAIL is invalid"
end
if facilitator_email && !og_emails.include?(facilitator_email)
  raise ArgumentError, "RAILS_BUILDERS_FACILITATOR_EMAIL must also appear in RAILS_BUILDERS_OG_EMAILS"
end

Rails.application.config.x.rails_builders.og_emails = og_emails.freeze
Rails.application.config.x.rails_builders.facilitator_email = facilitator_email
