class CommunityStatistic < ApplicationRecord
  REGISTRATIONS_SINCE = Time.utc(2026, 9, 1).freeze

  validates :id, inclusion: { in: [ 1 ] }
  validates :cohorts_count, :cohort_finishers_count, :registrants_count,
    numericality: { only_integer: true, greater_than_or_equal_to: 0 }

  def self.current
    find_or_create_by!(id: 1)
  end
end
