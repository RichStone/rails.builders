class LoginSession < ApplicationRecord
  belongs_to :user

  generates_token_for :reauthentication, expires_in: 15.minutes

  scope :unexpired, -> { where("created_at > ?", 400.days.ago) }

  def recently_authenticated?
    created_at > 15.minutes.ago
  end
end
