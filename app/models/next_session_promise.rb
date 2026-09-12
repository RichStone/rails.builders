class NextSessionPromise < ApplicationRecord
  belongs_to :builder_session
  belongs_to :user

  encrypts :body
  normalizes :body, with: ->(value) { value.strip }

  validates :body, presence: true, length: { maximum: 500 }
  validates :user_id, uniqueness: { scope: :builder_session_id }
  validate :session_and_participant_are_eligible

  private

  def session_and_participant_are_eligible
    return unless builder_session

    errors.add(:builder_session, "does not allow session records") unless builder_session.session_record_writable?
    errors.add(:user, "must have participated in the session") unless builder_session.participated?(user)
  end
end
