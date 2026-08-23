class BuilderSessionAttendance < ApplicationRecord
  ROLES = %w[builder facilitator].freeze
  STATUSES = %w[absent present].freeze
  SPEAKER_STATES = %w[queued speaking completed skipped].freeze

  belongs_to :builder_session
  belongs_to :user, optional: true

  validates :display_name, presence: true, length: { maximum: 100 }
  validates :role, inclusion: { in: ROLES }
  validates :status, inclusion: { in: STATUSES }
  validates :speaker_state, inclusion: { in: SPEAKER_STATES }, allow_nil: true
  validates :speaker_position, numericality: { only_integer: true, greater_than: 0 }, allow_nil: true
  validates :speaker_position, uniqueness: { scope: :builder_session_id }, allow_nil: true
  validates :speaker_allotted_seconds, numericality: { only_integer: true, greater_than_or_equal_to: 0 }, allow_nil: true
end
