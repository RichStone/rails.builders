require "net/http"
require "json"

class ClickfunnelsNewsletter
  class TransientError < StandardError; end
  class PermanentError < StandardError; end

  BASE_URL = "https://humanontheloop.myclickfunnels.com/api/v2"
  WORKSPACE_ID = "477369"
  TAG_ID = "448334"
  TAG_PUBLIC_ID = "jYqAlB"

  def initialize(user)
    @user = user
  end

  def subscribe!
    contact = post("/workspaces/#{WORKSPACE_ID}/contacts/upsert", contact: contact_attributes)
    contact_id = contact.fetch("id").to_s
    contact_public_id = contact.fetch("public_id")
    result = { contact_id: contact_id, contact_public_id: contact_public_id }
    return result.merge(status: "blocked_suppressed") if suppressed?(contact)

    post("/contacts/#{contact_public_id}/applied_tags", contacts_applied_tag: { tag_id: TAG_ID }) unless tagged?(contact)
    result.merge(status: "subscribed")
  end

  private

  attr_reader :user

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
      tag["id"].to_s == TAG_ID || tag["public_id"] == TAG_PUBLIC_ID
    end
  end

  def post(path, body)
    uri = URI("#{BASE_URL}#{path}")
    request = Net::HTTP::Post.new(uri)
    request["Authorization"] = "Bearer #{ENV.fetch("CLICKFUNNELS_API_TOKEN")}"
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
