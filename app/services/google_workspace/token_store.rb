require "googleauth/token_store"
require "json"

module GoogleWorkspace
  class TokenStore < Google::Auth::TokenStore
    EMPTY_TOKEN = "{}"

    def initialize(connection:)
      @connection = connection
    end

    def load(_id)
      token = connection.oauth_token_json
      return if token.blank? || JSON.parse(token).empty?

      token
    end

    def store(_id, token)
      persist(token)
      token
    end

    def delete(_id)
      persist(EMPTY_TOKEN)
      nil
    end

    private

    attr_reader :connection

    def persist(token)
      connection.update!(oauth_token_json: token)
    end
  end
end
