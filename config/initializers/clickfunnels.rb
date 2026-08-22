credentials = Rails.env.production? ? (Rails.application.credentials.dig(:clickfunnels) || {}) : {}
settings = {
  enabled: Rails.env.production?,
  api_token: credentials[:api_token],
  base_url: credentials[:base_url],
  workspace_id: credentials[:workspace_id],
  tag_id: credentials[:newsletter_tag_id],
  tag_public_id: credentials[:newsletter_tag_public_id]
}

if Rails.env.development? && ENV["CLICKFUNNELS_SMOKE_TEST_PROFILE"].present?
  profile = ENV.fetch("CLICKFUNNELS_SMOKE_TEST_PROFILE")
  raise ArgumentError, "Only the isolated test-only ClickFunnels profile is allowed locally" unless profile == "test-only"

  token_io = IO.new(Integer(ENV.fetch("CLICKFUNNELS_API_TOKEN_FD")), autoclose: false)
  settings.merge!(
    enabled: true,
    api_token: token_io.read.strip,
    base_url: "https://testonly.myclickfunnels.com/api/v2",
    workspace_id: "382270",
    tag_id: "455783",
    tag_public_id: "JnQAnZ"
  )
end

settings.each { |key, value| Rails.application.config.x.clickfunnels.public_send("#{key}=", value) }
