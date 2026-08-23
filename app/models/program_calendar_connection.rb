class ProgramCalendarConnection < ApplicationRecord
  STATUSES = %w[authorizing connected error reauthorization_required].freeze

  belongs_to :program
  belongs_to :facilitator, class_name: "User"

  encrypts :oauth_token_json

  validates :google_account_email, :google_calendar_id, :google_calendar_name, :oauth_token_json, presence: true
  validates :google_account_email, length: { maximum: 320 }
  validates :google_calendar_id, :google_calendar_name, :google_data_owner, length: { maximum: 500 }, allow_nil: true
  validates :google_calendar_time_zone, length: { maximum: 100 }, allow_nil: true
  validates :last_error_code, length: { maximum: 100 }, allow_nil: true
  validates :status, inclusion: { in: STATUSES }
  validate :facilitator_matches_program

  private

  def facilitator_matches_program
    return if program.nil? || facilitator.nil? || program.main_facilitator == facilitator

    errors.add(:facilitator, "must be the Program's main facilitator")
  end
end
