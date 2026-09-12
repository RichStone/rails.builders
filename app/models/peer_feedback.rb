class PeerFeedback < ApplicationRecord
  SENTIMENTS = %w[encouraging constructive idea question].freeze
  SOURCES = %w[transcript chat].freeze

  belongs_to :builder_session
  belongs_to :author, class_name: "User"
  belongs_to :recipient, class_name: "User"

  encrypts :body
  normalizes :body, with: ->(value) { value.strip }

  validates :body, presence: true, length: { maximum: 700 }
  validates :sentiment, inclusion: { in: SENTIMENTS }
  validates :source, inclusion: { in: SOURCES }
  validates :source_key, presence: true, length: { maximum: 200 }, uniqueness: { scope: :builder_session_id }
  validate :session_and_participants_are_eligible

  private

  def session_and_participants_are_eligible
    return unless builder_session

    errors.add(:builder_session, "does not allow session records") unless builder_session.session_record_writable?
    errors.add(:author, "must have participated in the session") unless builder_session.participated?(author)
    recipient_expected = recipient.present? && (builder_session.assigned_facilitator_id == recipient_id || builder_session.attendances.exists?(user_id: recipient_id))
    errors.add(:recipient, "must have been expected at the session") unless recipient_expected
    errors.add(:recipient, "must differ from the author") if author_id.present? && author_id == recipient_id
  end
end
