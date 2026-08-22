require "google/apis/calendar_v3"
require "google/apis/meet_v2"
require "googleauth"
require "googleauth/web_user_authorizer"
require "securerandom"

module GoogleWorkspace
  class Authorization
    SCOPES = [
      Google::Apis::CalendarV3::AUTH_CALENDAR_CALENDARLIST_READONLY,
      Google::Apis::CalendarV3::AUTH_CALENDAR_EVENTS_OWNED_READONLY,
      Google::Apis::MeetV2::AUTH_MEETINGS_SPACE_READONLY
    ].freeze

    def self.generate_code_verifier
      SecureRandom.alphanumeric(64)
    end

    def initialize(connection:, callback_uri: nil, code_verifier: nil, client_id: nil)
      @connection = connection
      @authorizer = Google::Auth::WebUserAuthorizer.new(
        client_id || configured_client_id,
        SCOPES,
        TokenStore.new(connection: connection),
        callback_uri: callback_uri,
        code_verifier: code_verifier
      )
    end

    def authorization_url(request:, redirect_to:, login_hint:)
      authorizer.get_authorization_url(request: request, redirect_to: redirect_to, login_hint: login_hint)
    end

    def authorize!(request)
      authorizer.handle_auth_callback(token_key, request).first
    end

    def credentials
      authorizer.get_credentials(token_key)
    end

    def revoke!
      authorizer.revoke_authorization(token_key)
    end

    private

    attr_reader :authorizer, :connection

    def configured_client_id
      credentials = Rails.application.credentials
      id = ENV["GOOGLE_OAUTH_CLIENT_ID"].presence || credentials.dig(:google_workspace, :client_id)
      secret = ENV["GOOGLE_OAUTH_CLIENT_SECRET"].presence || credentials.dig(:google_workspace, :client_secret)
      raise ConfigurationError, "Google OAuth client credentials are not configured" if id.blank? || secret.blank?

      Google::Auth::ClientId.new(id, secret)
    end

    def token_key
      "program-calendar-connection:#{connection.id || connection.program_id}"
    end
  end
end
