require "net/http"
require "json"

class ClickfunnelsNewsletter
  class TransientError < StandardError; end
  class PermanentError < StandardError; end

  Configuration = Data.define(:enabled, :api_token, :base_url, :workspace_id, :tag_id, :tag_public_id) do
    def configured?
      api_token.present? && base_url.present? && workspace_id.present? && tag_id.present?
    end
  end

  def self.configuration
    settings = Rails.application.config.x.clickfunnels
    Configuration.new(
      enabled: settings.enabled,
      api_token: settings.api_token,
      base_url: settings.base_url,
      workspace_id: settings.workspace_id,
      tag_id: settings.tag_id,
      tag_public_id: settings.tag_public_id
    )
  end

  def initialize(user, configuration: self.class.configuration)
    @user = user
    @configuration = configuration
  end

  def subscribe!
    contact = post("/workspaces/#{configuration.workspace_id}/contacts/upsert", contact: contact_attributes)
    contact_id = contact.fetch("id").to_s
    contact_public_id = contact.fetch("public_id")
    result = { contact_id: contact_id, contact_public_id: contact_public_id }
    return result.merge(status: "blocked_suppressed") if suppressed?(contact)

    post("/contacts/#{contact_public_id}/applied_tags", contacts_applied_tag: { tag_id: configuration.tag_id }) unless tagged?(contact)
    result.merge(status: "subscribed")
  end

  private

  attr_reader :configuration, :user

  def contact_attributes
    attributes = { email_address: user.email }
    first_name, *last_name = user.name.to_s.split
    attributes[:first_name] = first_name if first_name.present?
    attributes[:last_name] = last_name.join(" ") if last_name.any?
    attributes
  end

  def suppressed?(contact)
    contact["is_active"] == false || contact["unsubscribed_at"].present? || contact["email_suppression_reason"].present?
  end

  def tagged?(contact)
    Array(contact["tags"]).any? do |tag|
      tag["id"].to_s == configuration.tag_id.to_s ||
        (configuration.tag_public_id.present? && tag["public_id"] == configuration.tag_public_id)
    end
  end

  def post(path, body)
    uri = URI("#{configuration.base_url}#{path}")
    request = Net::HTTP::Post.new(uri)
    request["Authorization"] = "Bearer #{configuration.api_token}"
    request["Content-Type"] = "application/json"
    request["User-Agent"] = "RailsBuilders/1.0 (https://rails.builders)"
    request.body = JSON.generate(body)
    response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true, read_timeout: 10, open_timeout: 5) { |http| http.request(request) }
    handle_response(response)
  rescue Net::OpenTimeout, Net::ReadTimeout, Errno::ECONNRESET, Errno::ECONNREFUSED => error
    raise TransientError, error.message
  end

  def handle_response(response)
    return response.body.present? ? JSON.parse(response.body) : {} if response.is_a?(Net::HTTPSuccess)
    raise TransientError, "ClickFunnels request failed: #{response.code}" if response.code.to_i == 429 || response.code.to_i >= 500

    raise PermanentError, "ClickFunnels request failed: #{response.code}"
  end
end
