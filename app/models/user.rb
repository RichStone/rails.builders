class User < ApplicationRecord
  ENROLLMENT_STATUSES = %w[unverified waitlisted offered active declined expired withdrawn].freeze
  SLACK_STATUSES = %w[manual_pending invited active removed].freeze
  CLICKFUNNELS_SYNC_STATUSES = %w[not_requested pending missing_configuration subscribed blocked_suppressed failed].freeze

  generates_token_for :email_verification, expires_in: 30.minutes do
    sign_in_token_version
  end

  generates_token_for :newsletter_confirmation, expires_in: 7.days do
    newsletter_token_version
  end

  has_many :products, dependent: :destroy
  has_one_attached :avatar

  normalizes :email, with: ->(email) { email.strip.downcase }
  normalizes :name, :testimonial, with: ->(value) { value.strip }

  validates :email, presence: true, uniqueness: { case_sensitive: false }, length: { maximum: 320 }, format: { with: URI::MailTo::EMAIL_REGEXP }
  validates :name, length: { maximum: 100 }, allow_nil: true
  validates :testimonial, length: { maximum: 2_000 }, allow_nil: true
  validates :enrollment_status, inclusion: { in: ENROLLMENT_STATUSES }
  validates :slack_status, inclusion: { in: SLACK_STATUSES }
  validates :clickfunnels_sync_status, inclusion: { in: CLICKFUNNELS_SYNC_STATUSES }
  validates :waitlist_rank, numericality: { only_integer: true, greater_than: 0 }, allow_nil: true
  validates :newsletter_requested_ip, length: { maximum: 45 }, allow_nil: true
  validates :newsletter_user_agent, length: { maximum: 500 }, allow_nil: true
  validates :newsletter_consent_version, length: { maximum: 50 }, allow_nil: true
  validates :clickfunnels_contact_id, :clickfunnels_contact_public_id, length: { maximum: 100 }, allow_nil: true
  validate :avatar_is_a_safe_image
  validate :public_profile_is_complete

  after_update_commit :deliver_enrollment_notifications, if: :saved_change_to_enrollment_status?
  before_destroy { @released_capacity = (active? || offered?) && !facilitator? }
  after_destroy_commit { Program.current.promote_waitlist! if @released_capacity }

  scope :og, -> { where(og: true) }
  scope :active, -> { where(enrollment_status: "active") }
  scope :offered, -> { where(enrollment_status: "offered") }
  scope :waitlisted, -> { where(enrollment_status: "waitlisted") }
  scope :publicly_visible, -> { where(public_profile: true) }

  def verified? = verified_at.present?
  def active? = enrollment_status == "active"
  def offered? = enrollment_status == "offered"
  def waitlisted? = enrollment_status == "waitlisted"

  def complete_verification!
    program = Program.current
    promotion_needed = false

    program.with_lock do
      update!(verified_at: Time.current) unless verified?

      if enrollment_status == "unverified"
        if og? && program.og_priority? && program.seat_available?
          issue_offer!
        else
          join_waitlist!
          promotion_needed = !program.og_priority?
        end
      end
    end

    program.promote_waitlist! if promotion_needed
    self
  end

  def issue_offer!
    update!(enrollment_status: "offered", offer_expires_at: 72.hours.from_now, waitlist_joined_at: nil, waitlist_rank: nil)
  end

  def accept_offer!
    expired = false

    with_lock do
      return false unless offered?

      if offer_expires_at <= Time.current
        update!(enrollment_status: "expired", offer_expires_at: nil)
        expired = true
      else
        update!(enrollment_status: "active", offer_expires_at: nil)
      end
    end

    Program.current.promote_waitlist! if expired
    !expired
  end

  def expire_offer!
    expired = with_lock do
      next false unless offered?

      update!(enrollment_status: "expired", offer_expires_at: nil)
      true
    end

    Program.current.promote_waitlist! if expired
    false
  end

  def opt_into_waitlist!
    program = Program.current
    rejoined = program.with_lock do
      next false unless reload.enrollment_status.in?(%w[declined expired withdrawn])

      join_waitlist!
      true
    end

    return false unless rejoined

    program.promote_waitlist! unless program.og_priority?
    true
  end

  def decline_offer!
    declined = with_lock do
      next false unless offered?

      update!(enrollment_status: "declined", offer_expires_at: nil)
      true
    end
    Program.current.promote_waitlist! if declined
    declined
  end

  def withdraw_seat!
    withdrawn = with_lock do
      next false unless active?

      update!(enrollment_status: "withdrawn")
      true
    end
    Program.current.promote_waitlist! if withdrawn
    withdrawn
  end

  def join_waitlist!
    update!(
      enrollment_status: "waitlisted",
      offer_expires_at: nil,
      waitlist_joined_at: Time.current,
      waitlist_rank: (User.maximum(:waitlist_rank) || 0) + 1
    )
  end

  def waitlist_position
    return unless waitlisted?

    Program.current.ordered_waitlist.pluck(:id).index(id)&.+(1)
  end

  def focus_product
    products.find_by(focus: true) || products.first
  end

  private

  def deliver_enrollment_notifications
    program = Program.current
    return if waitlisted? && !program.og_priority? && !program.promotions_paused? && program.seat_available?

    UserMailer.enrollment_status(self, enrollment_status, waitlist_position).deliver_later
    AdministratorMailer.enrollment_status(self, enrollment_status).deliver_later if User.where(administrator: true).exists?
    UserMailer.offer_reminder(self).deliver_later(wait_until: offer_expires_at - 24.hours) if offered? && offer_expires_at > 24.hours.from_now
  end

  def avatar_is_a_safe_image
    return unless avatar.attached?

    errors.add(:avatar, "must be a PNG, JPEG, or WebP image") unless avatar.content_type.in?(%w[image/png image/jpeg image/webp])
    errors.add(:avatar, "must be smaller than 5 MB") if avatar.byte_size > 5.megabytes
  end

  def public_profile_is_complete
    return unless public_profile?

    errors.add(:public_profile, "requires your name and a focus product") if name.blank? || focus_product.nil?
  end
end
