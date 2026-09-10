require "net/http"

class Turnstile
  ENDPOINT = URI("https://challenges.cloudflare.com/turnstile/v0/siteverify")

  def self.enabled?
    Rails.configuration.x.turnstile.enabled
  end

  def self.site_key
    Rails.configuration.x.turnstile.site_key
  end

  def self.verify(token:, hostname:)
    return :verified unless enabled?
    return :rejected unless token.is_a?(String) && token.valid_encoding? && token.present? && token.bytesize <= 2048
    return :rejected unless Rails.configuration.x.turnstile.hostnames.include?(hostname)
    return :unavailable if Rails.configuration.x.turnstile.secret_key.blank? || site_key.blank?

    request = Net::HTTP::Post.new(ENDPOINT)
    request.set_form_data(secret: Rails.configuration.x.turnstile.secret_key, response: token)
    response = Net::HTTP.start(ENDPOINT.host, ENDPOINT.port, use_ssl: true, open_timeout: 2, read_timeout: 3, write_timeout: 3, max_retries: 0) do |http|
      http.request(request)
    end
    return :unavailable unless response.code.to_i.between?(200, 299)

    result = JSON.parse(response.body)
    return :unavailable unless result.is_a?(Hash) && [ true, false ].include?(result["success"])
    return :unavailable if (Array(result["error-codes"]) & %w[internal-error invalid-input-secret missing-input-secret bad-request]).any?

    result["success"] == true && result["hostname"] == hostname && result["action"] == "sign_in" ? :verified : :rejected
  rescue JSON::ParserError, IOError, SocketError, SystemCallError, Timeout::Error, OpenSSL::SSL::SSLError, Net::ProtocolError
    :unavailable
  end
end
