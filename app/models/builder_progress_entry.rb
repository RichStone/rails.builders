class BuilderProgressEntry < ApplicationRecord
  belongs_to :builder_session
  belongs_to :user

  encrypts :body, :comparison, :source
  normalizes :body, :comparison, :source, with: ->(value) { value.strip.presence }

  validates :body, presence: true, length: { maximum: 1200 }
  validates :source, presence: true, length: { maximum: 500 }
  validates :comparison, length: { maximum: 300 }
  validate :session_and_builder_are_eligible

  scope :for_program, ->(program) { where(builder_session: program.builder_sessions.with_session_records) }
  scope :recent_first, -> { joins(:builder_session).order(builder_sessions: { scheduled_starts_at: :desc }).order(:id) }

  private

  def session_and_builder_are_eligible
    return unless builder_session

    errors.add(:builder_session, "does not allow session records") unless builder_session.session_record_writable?
    unless user && (builder_session.assigned_facilitator_id == user_id || builder_session.attendances.exists?(user_id:))
      errors.add(:user, "must be on the session roster")
    end
  end
end
