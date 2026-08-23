require "uri"

module GoogleWorkspace
  module MeetLink
    CODE_PATTERN = /\A[a-z]{3}-[a-z]{4}-[a-z]{3}\z/

    module_function

    def code(value)
      uri = URI.parse(value.to_s)
      return unless uri.scheme == "https" && uri.host&.downcase == "meet.google.com"
      return unless uri.userinfo.nil? && uri.port == 443

      candidate = uri.path.split("/").reject(&:blank?).first.to_s.downcase
      candidate if candidate.match?(CODE_PATTERN)
    rescue URI::InvalidURIError
      nil
    end

    def url(value)
      meeting_code = code(value)
      "https://meet.google.com/#{meeting_code}" if meeting_code
    end

    def canonical?(value)
      value.present? && value == url(value)
    end
  end
end
