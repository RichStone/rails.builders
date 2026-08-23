class BuilderSessionPause < ApplicationRecord
  belongs_to :builder_session

  validates :started_at, presence: true
  validate :end_follows_start

  private

  def end_follows_start
    return unless started_at && ended_at && ended_at < started_at

    errors.add(:ended_at, "must be on or after the pause start")
  end
end
