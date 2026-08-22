class User < ApplicationRecord
  ENROLLMENT_STATUSES = %w[unverified waitlisted offered active declined expired withdrawn left_waitlist removed].freeze
  SLACK_STATUSES = %w[manual_pending invited active removed].freeze
  SLACK_DESIRED_STATES = %w[absent present].freeze
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
  validates :slack_desired_state, inclusion: { in: SLACK_DESIRED_STATES }
  validates :clickfunnels_sync_status, inclusion: { in: CLICKFUNNELS_SYNC_STATUSES }
  validates :waitlist_rank, numericality: { only_integer: true, greater_than: 0 }, allow_nil: true
  validates :newsletter_requested_ip, length: { maximum: 45 }, allow_nil: true
  validates :newsletter_user_agent, length: { maximum: 500 }, allow_nil: true
  validates :newsletter_consent_version, length: { maximum: 50 }, allow_nil: true
  validates :clickfunnels_contact_id, :clickfunnels_contact_public_id, length: { maximum: 100 }, allow_nil: true
  validate :avatar_is_a_safe_image
  validate :public_profile_is_complete
  validate :preserve_last_verified_administrator, if: :will_save_change_to_administrator?

  before_validation :set_slack_desired_state
  before_validation :clear_public_profile_approval_without_opt_in
  after_update_commit :deliver_enrollment_notifications, if: :saved_change_to_enrollment_status?
  before_destroy :prevent_last_verified_administrator_deletion

  scope :og, -> { where(og: true) }
  scope :active, -> { where(enrollment_status: "active") }
  scope :offered, -> { where(enrollment_status: "offered") }
  scope :waitlisted, -> { where(enrollment_status: "waitlisted") }
  scope :publicly_visible, -> { where(public_profile: true, public_profile_approved: true) }

  def verified? = verified_at.present?
  def active? = enrollment_status == "active"
  def offered? = enrollment_status == "offered"
  def waitlisted? = enrollment_status == "waitlisted"
  def left_waitlist? = enrollment_status == "left_waitlist"
  def removed? = enrollment_status == "removed"
  def publicly_visible? = public_profile? && public_profile_approved?
  def waitlist_eligible? = verified? && enrollment_status.in?(%w[declined expired withdrawn left_waitlist])

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
    update_waitlist_participation!(joined: true)
  end

  def update_waitlist_participation!(joined:)
    program = Program.current
    changed = program.with_lock do
      with_lock do
        if joined
          next false unless waitlist_eligible?

          join_waitlist!
        else
          next false unless waitlisted?

          clear_seat_and_queue!(status: "left_waitlist")
        end
        true
      end
    end

    program.promote_waitlist!(limit: 1) if joined && changed
    changed
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
    update_active_membership!(active: false)
  end

  def update_active_membership!(active:)
    return false if active

    Program.current.release_seat! do
      with_lock do
        next false unless active?

        update!(enrollment_status: "withdrawn")
        [ !facilitator?, true ]
      end
    end
  end

  def remove_from_program!
    Program.current.release_seat! do
      with_lock do
        next false if removed?

        released_seat = (active? || offered?) && !facilitator?
        clear_seat_and_queue!(status: "removed")
        [ released_seat, true ]
      end
    end
  end

  def reinstate_enrollment!
    Program.current.with_lock do
      with_lock do
        next false unless removed?

        clear_seat_and_queue!(status: "left_waitlist")
        true
      end
    end
  end

  def update_administrator_role!(administrator:)
    Program.current.with_lock do
      with_lock do
        next false if administrator? == administrator
        next false if !administrator && last_verified_administrator?

        update!(administrator: administrator)
        true
      end
    end
  end

  def delete_account!
    Program.current.release_seat! do
      with_lock do
        next false if last_verified_administrator?

        released_seat = (active? || offered?) && !facilitator?
        destroy!
        [ released_seat, true ]
      end
    end
  rescue ActiveRecord::RecordNotFound
    false
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

  def clear_seat_and_queue!(status:)
    update!(enrollment_status: status, offer_expires_at: nil, waitlist_joined_at: nil, waitlist_rank: nil)
  end

  def set_slack_desired_state
    self.slack_desired_state = active? ? "present" : "absent"
  end

  def clear_public_profile_approval_without_opt_in
    self.public_profile_approved = false unless public_profile?
  end

  def last_verified_administrator?
    administrator_in_database && verified? && User.where(administrator: true).where.not(verified_at: nil).where.not(id: id).none?
  end

  def preserve_last_verified_administrator
    return unless administrator_in_database && !administrator? && verified? && last_verified_administrator?

    errors.add(:administrator, "cannot be removed from the last verified administrator")
  end

  def prevent_last_verified_administrator_deletion
    return unless last_verified_administrator?

    errors.add(:base, "The last verified administrator cannot be deleted")
    throw :abort
  end

  def deliver_enrollment_notifications
    program = Program.current
    immediately_promotable = waitlisted? && !program.promotions_paused? && program.seat_available? && (!program.og_priority? || og?)
    return if immediately_promotable

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
