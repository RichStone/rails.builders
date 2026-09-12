class BuilderSessionChatLog < ApplicationRecord
  SOURCES = %w[manual google_chat google_meet].freeze

  belongs_to :builder_session

  encrypts :content

  validates :builder_session_id, uniqueness: true
  validates :content, presence: true, length: { maximum: 1.megabyte }
  validates :source, inclusion: { in: SOURCES }
  validates :imported_at, presence: true
  validate :session_allows_records

  private

  def session_allows_records
    if builder_session && !builder_session.session_record_writable?
      errors.add(:builder_session, "does not allow session records")
    end
  end
end
