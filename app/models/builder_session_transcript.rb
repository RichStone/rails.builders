class BuilderSessionTranscript < ApplicationRecord
  STATES = %w[pending processing ready unavailable deleted].freeze
  SOURCES = %w[google manual].freeze
  AUTOMATIC_IMPORT_STATES = %w[pending processing].freeze
  MANUAL_FALLBACK_STATES = (AUTOMATIC_IMPORT_STATES + [ "unavailable" ]).freeze
  PROCESSING_TIPS = [
    "Ask for the smallest next move, not the perfect plan.",
    "A useful meeting leaves somebody with a clearer decision.",
    "Name the blocker plainly; clever euphemisms rarely unblock code.",
    "Protect the hangout. Trust often arrives after the agenda ends."
  ].freeze

  belongs_to :builder_session

  after_update_commit -> { builder_session.touch }

  encrypts :content
  encrypts :google_conference_record_name
  encrypts :google_transcript_names

  validates :state, inclusion: { in: STATES }
  validates :source, inclusion: { in: SOURCES }, allow_nil: true
  validates :attempts, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :last_error_code, length: { maximum: 100 }, allow_nil: true
  validates :content, length: { maximum: 1.megabyte }, allow_nil: true
  validates :content, presence: true, if: -> { state == "ready" }

  def transcript_names
    JSON.parse(google_transcript_names.presence || "[]")
  end

  def processing_tip
    PROCESSING_TIPS[builder_session_id % PROCESSING_TIPS.length]
  end

  def replace_with_manual!(value)
    with_lock do
      unless state.in?(MANUAL_FALLBACK_STATES)
        errors.add(:state, "does not allow a replacement transcript")
        raise ActiveRecord::RecordInvalid, self
      end

      update!(
        state: "ready",
        source: "manual",
        content: value.to_s.strip.presence,
        google_conference_record_name: nil,
        google_transcript_names: nil,
        next_attempt_at: nil,
        imported_at: Time.current,
        deleted_at: nil,
        last_error_code: nil
      )
    end
  end

  def delete_content!
    update!(
      state: "deleted",
      content: nil,
      google_conference_record_name: nil,
      google_transcript_names: nil,
      next_attempt_at: nil,
      deleted_at: Time.current,
      last_error_code: nil
    )
  end
end
