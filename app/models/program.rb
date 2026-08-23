class Program < ApplicationRecord
  belongs_to :main_facilitator, class_name: "User", optional: true
  has_one :calendar_connection, class_name: "ProgramCalendarConnection", dependent: :destroy
  has_many :builder_sessions, dependent: :restrict_with_error

  normalizes :name, :format_points, :readiness_points, with: ->(value) { value.strip }

  validates :name, :starts_on, :ends_on, :format_points, :readiness_points, presence: true
  validates :name, length: { maximum: 100 }
  validates :capacity, numericality: { only_integer: true, greater_than: 0 }
  validate :ends_on_or_after_starts_on
  validate :main_facilitator_has_role

  def self.current
    first || create!(name: "Continuous r-AI-ls.Builders Edition", starts_on: Date.new(2026, 8, 20), ends_on: Date.new(2026, 12, 17), capacity: 9)
  end

  def occupied_seats
    User.where(enrollment_status: %w[offered active], facilitator: false).count
  end

  def places_left = [ capacity - occupied_seats, 0 ].max
  def started? = starts_on <= Date.current
  def seat_available? = occupied_seats < capacity

  def format_points_list
    format_points.lines(chomp: true).filter_map { |point| point.strip.presence }
  end

  def readiness_points_list
    readiness_points.lines(chomp: true).filter_map { |point| point.strip.presence }
  end

  def readiness_confirmed?(confirmed_points)
    confirmed = Array(confirmed_points).map(&:to_s).uniq.sort
    confirmed == readiness_points_list.each_index.map(&:to_s).sort
  end

  def ordered_waitlist
    User.waitlisted.order(Arel.sql("CASE WHEN waitlist_rank IS NULL THEN 1 ELSE 0 END"), :waitlist_rank, :waitlist_joined_at, :id)
  end

  def open_waitlist!
    update!(og_priority: false)
    promote_waitlist!
  end

  def promote_waitlist!(limit: nil)
    with_lock do
      promote_waitlist(limit: limit)
    end
  end

  def release_seat!
    with_lock do
      outcome = yield
      if outcome
        released, result = outcome
        promote_waitlist(limit: 1) if released
        result
      else
        false
      end
    end
  end

  def expire_offers!
    User.offered.where(offer_expires_at: ..Time.current).find_each(&:expire_offer!)
  end

  def calendar_credentials_in_use?
    return true if builder_sessions.active.exists?

    builder_sessions.joins(:transcript)
      .where(builder_session_transcripts: { state: BuilderSessionTranscript::AUTOMATIC_IMPORT_STATES })
      .exists?
  end

  private

  def promote_waitlist(limit:)
    promoted = 0
    while !promotions_paused? && seat_available? && (!limit || promoted < limit) && (user = next_eligible_waitlist_entry)
      user.issue_offer!
      promoted += 1
    end
  end

  def next_eligible_waitlist_entry
    og_priority? ? ordered_waitlist.where(og: true).first : ordered_waitlist.first
  end

  def ends_on_or_after_starts_on
    return unless starts_on && ends_on && ends_on < starts_on

    errors.add(:ends_on, :after_or_equal_to, message: "must be on or after the start date")
  end

  def main_facilitator_has_role
    return if main_facilitator.nil? || main_facilitator.facilitator?

    errors.add(:main_facilitator, "must have the Facilitator role")
  end
end
