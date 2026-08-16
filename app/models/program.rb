class Program < ApplicationRecord
  normalizes :name, with: ->(name) { name.strip }

  validates :name, :starts_on, :ends_on, presence: true
  validates :name, length: { maximum: 100 }
  validates :capacity, numericality: { only_integer: true, greater_than: 0 }
  validate :ends_on_or_after_starts_on

  def self.current
    first || create!(name: "Continuous", starts_on: Date.new(2026, 8, 20), ends_on: Date.new(2026, 12, 17), capacity: 9)
  end

  def occupied_seats
    User.where(enrollment_status: %w[offered active], facilitator: false).count
  end

  def seat_available? = occupied_seats < capacity

  def ordered_waitlist
    User.waitlisted.order(Arel.sql("CASE WHEN waitlist_rank IS NULL THEN 1 ELSE 0 END"), :waitlist_rank, :waitlist_joined_at, :id)
  end

  def open_waitlist!
    update!(og_priority: false)
    promote_waitlist!
  end

  def promote_waitlist!
    with_lock do
      while !promotions_paused? && seat_available? && (user = ordered_waitlist.first)
        user.issue_offer!
      end
    end
  end

  def expire_offers!
    User.offered.where(offer_expires_at: ..Time.current).find_each(&:expire_offer!)
  end

  private

  def ends_on_or_after_starts_on
    return unless starts_on && ends_on && ends_on < starts_on

    errors.add(:ends_on, :after_or_equal_to, message: "must be on or after the start date")
  end
end
