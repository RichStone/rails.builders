require "test_helper"

class UserTest < ActiveSupport::TestCase
  READINESS_CONFIRMATION = %w[0 1 2 3 4 5].freeze

  setup do
    @program = Program.create!(
      name: "Continuous",
      starts_on: Date.new(2026, 8, 20),
      ends_on: Date.new(2026, 12, 17),
      capacity: 10,
      og_priority: true
    )
  end

  test "verified OG receives a 72 hour offer during OG Priority" do
    user = User.create!(email: "builder@example.com", og: true)

    travel_to(Time.zone.local(2026, 8, 9, 12)) { user.complete_verification! }

    assert user.verified?
    assert_equal "offered", user.enrollment_status
    assert_equal Time.zone.local(2026, 8, 12, 12), user.offer_expires_at
    assert_equal 1, @program.reload.occupied_seats
  end

  test "opening general admission does not enroll inactive registrations" do
    first = User.create!(email: "first@example.com")
    second = User.create!(email: "second@example.com")
    travel_to(Time.zone.local(2026, 8, 9, 10)) { first.complete_verification! }
    travel_to(Time.zone.local(2026, 8, 9, 11)) { second.complete_verification! }

    assert_equal "inactive", first.reload.enrollment_status
    assert_equal "inactive", second.reload.enrollment_status
    assert_empty @program.ordered_waitlist

    @program.open_waitlist!

    assert first.reload.inactive?
    assert second.reload.inactive?
    assert_not @program.reload.og_priority?
  end

  test "a non-OG registering after general admission opens needs readiness before receiving capacity" do
    @program.update!(og_priority: false)
    user = User.create!(email: "new@example.com")

    user.complete_verification!

    assert user.reload.inactive?
    assert user.opt_into_waitlist!(readiness: READINESS_CONFIRMATION)
    assert user.reload.offered?
  end

  test "recipient confirms a current offer without completing a profile" do
    user = User.create!(email: "builder@example.com", og: true)
    user.complete_verification!

    assert user.accept_offer!
    assert_equal "active", user.reload.enrollment_status
    assert_equal "present", user.slack_desired_state
    assert_nil user.name
    assert_not user.public_profile?
  end

  test "active enrollment owns desired Slack membership independently of profile visibility" do
    user = User.create!(email: "builder@example.com", verified_at: Time.current, enrollment_status: "active")

    assert_equal "present", user.slack_desired_state
    user.update!(public_profile: false)

    assert user.reload.active?
    assert_equal "present", user.slack_desired_state
  end

  test "expired offer promotes the queue and requires explicit re-entry" do
    @program.update!(capacity: 1, og_priority: false)
    first = User.create!(email: "first@example.com")
    second = User.create!(email: "second@example.com")
    first.complete_verification!
    second.complete_verification!
    first.opt_into_waitlist!(readiness: READINESS_CONFIRMATION)
    second.opt_into_waitlist!(readiness: READINESS_CONFIRMATION)

    travel_to(73.hours.from_now) { first.expire_offer! }

    assert_equal "expired", first.reload.enrollment_status
    assert_equal "offered", second.reload.enrollment_status

    first.opt_into_waitlist!(readiness: READINESS_CONFIRMATION)

    assert first.reload.waitlisted?
    assert_equal 1, first.waitlist_position
  end

  test "repeated verification does not extend an offer" do
    user = User.create!(email: "builder@example.com", og: true)
    travel_to(Time.zone.local(2026, 8, 9, 12)) { user.complete_verification! }
    original_expiry = user.offer_expires_at

    travel_to(2.hours.from_now) { user.complete_verification! }

    assert_equal original_expiry, user.reload.offer_expires_at
  end

  test "deleting an active account releases capacity and promotes the queue" do
    @program.update!(capacity: 1, og_priority: false)
    active = User.create!(email: "active@example.com", verified_at: Time.current, enrollment_status: "active")
    waiting = User.create!(email: "waiting@example.com", verified_at: Time.current, enrollment_status: "waitlisted", waitlist_joined_at: Time.current, waitlist_rank: 1)

    assert active.delete_account!

    assert waiting.reload.offered?
  end

  test "turning active membership off releases one seat and cannot turn it directly on" do
    @program.update!(capacity: 3, og_priority: false)
    active = User.create!(email: "active@example.com", verified_at: Time.current, enrollment_status: "active")
    first = User.create!(email: "first@example.com", verified_at: Time.current, enrollment_status: "waitlisted", waitlist_joined_at: 2.hours.ago, waitlist_rank: 1)
    second = User.create!(email: "second@example.com", verified_at: Time.current, enrollment_status: "waitlisted", waitlist_joined_at: 1.hour.ago, waitlist_rank: 2)

    assert active.update_active_membership!(active: false)
    assert_equal "withdrawn", active.reload.enrollment_status
    assert_equal "absent", active.slack_desired_state
    assert first.reload.offered?
    assert second.reload.waitlisted?, "one released seat must promote at most one builder"

    assert_not active.update_active_membership!(active: false), "repeated switch-off must be harmless"
    assert_not active.update_active_membership!(active: true), "membership cannot be switched directly on"
    assert_equal "withdrawn", active.reload.enrollment_status
    assert second.reload.waitlisted?
  end

  test "waitlist participation joins at the end and leaves idempotently" do
    @program.update!(capacity: 1, og_priority: false)
    User.create!(email: "active@example.com", verified_at: Time.current, enrollment_status: "active")
    User.create!(email: "waiting@example.com", verified_at: Time.current, enrollment_status: "waitlisted", waitlist_joined_at: 2.hours.ago, waitlist_rank: 4)
    user = User.create!(email: "returning@example.com", verified_at: Time.current, enrollment_status: "withdrawn")

    travel_to(Time.zone.local(2026, 8, 22, 12)) do
      assert user.update_waitlist_participation!(joined: true, readiness: READINESS_CONFIRMATION)
      assert user.reload.waitlisted?
      assert_equal 5, user.waitlist_rank
      assert_equal Time.current, user.waitlist_joined_at
      joined_at = user.waitlist_joined_at

      assert_not user.update_waitlist_participation!(joined: true, readiness: READINESS_CONFIRMATION), "repeated switch-on must not move the entry"
      assert_equal joined_at, user.reload.waitlist_joined_at
    end

    user.update_column(:offer_expires_at, 2.days.from_now)
    assert user.update_waitlist_participation!(joined: false)
    assert_equal "left_waitlist", user.reload.enrollment_status
    assert_nil user.waitlist_rank
    assert_nil user.waitlist_joined_at
    assert_nil user.offer_expires_at
    assert_not user.update_waitlist_participation!(joined: false), "repeated switch-off must be harmless"
  end

  test "waitlist opt-in promotes only an OG while OG Priority is active" do
    @program.update!(capacity: 1, og_priority: true)
    regular = User.create!(email: "regular@example.com", verified_at: Time.current, enrollment_status: "withdrawn")
    og = User.create!(email: "og@example.com", verified_at: Time.current, enrollment_status: "withdrawn", og: true)

    assert regular.update_waitlist_participation!(joined: true, readiness: READINESS_CONFIRMATION)
    assert regular.reload.waitlisted?

    assert og.update_waitlist_participation!(joined: true, readiness: READINESS_CONFIRMATION)
    assert og.reload.offered?
    assert regular.reload.waitlisted?
    assert_equal 1, @program.reload.occupied_seats
  end

  test "waitlist opt-in issues at most one offer" do
    @program.update!(capacity: 3, og_priority: false)
    first = User.create!(email: "first@example.com", verified_at: Time.current, enrollment_status: "waitlisted", waitlist_joined_at: 1.hour.ago, waitlist_rank: 1)
    joining = User.create!(email: "joining@example.com", verified_at: Time.current, enrollment_status: "left_waitlist")

    assert joining.update_waitlist_participation!(joined: true, readiness: READINESS_CONFIRMATION)

    assert first.reload.offered?
    assert joining.reload.waitlisted?
    assert_equal 1, @program.reload.occupied_seats
  end

  test "administrator removal releases one seat and reinstatement only restores eligibility" do
    @program.update!(capacity: 3, og_priority: false)
    user = User.create!(email: "active@example.com", verified_at: Time.current, enrollment_status: "active", slack_desired_state: "present")
    first = User.create!(email: "first@example.com", verified_at: Time.current, enrollment_status: "waitlisted", waitlist_joined_at: 2.hours.ago, waitlist_rank: 1)
    second = User.create!(email: "second@example.com", verified_at: Time.current, enrollment_status: "waitlisted", waitlist_joined_at: 1.hour.ago, waitlist_rank: 2)

    assert user.remove_from_program!
    assert_equal "removed", user.reload.enrollment_status
    assert_equal "absent", user.slack_desired_state
    assert first.reload.offered?
    assert second.reload.waitlisted?
    assert_not user.remove_from_program!, "repeated removal must be harmless"
    assert_not user.update_waitlist_participation!(joined: true, readiness: READINESS_CONFIRMATION), "removed builders cannot re-enter"

    assert user.reinstate_enrollment!
    assert_equal "left_waitlist", user.reload.enrollment_status
    assert_not user.offered?, "reinstatement must never grant a seat"
    assert_not user.reinstate_enrollment!, "repeated reinstatement must be harmless"
  end

  test "administrator removal handles offered and waitlisted builders" do
    @program.update!(capacity: 1, og_priority: false, promotions_paused: true)
    offered = User.create!(email: "offered@example.com", verified_at: Time.current, enrollment_status: "offered", offer_expires_at: 2.days.from_now)
    waitlisted = User.create!(email: "waiting@example.com", verified_at: Time.current, enrollment_status: "waitlisted", waitlist_joined_at: Time.current, waitlist_rank: 1)

    assert offered.remove_from_program!
    assert_equal "removed", offered.reload.enrollment_status
    assert_nil offered.offer_expires_at

    assert waitlisted.remove_from_program!
    assert_equal "removed", waitlisted.reload.enrollment_status
    assert_nil waitlisted.waitlist_joined_at
    assert_nil waitlisted.waitlist_rank
    assert_not waitlisted.remove_from_program!
  end

  test "the last verified administrator cannot be demoted or deleted" do
    administrator = User.create!(email: "admin@example.com", verified_at: Time.current, administrator: true)

    assert_raises(ActiveRecord::RecordInvalid) { administrator.update!(administrator: false) }
    assert administrator.reload.administrator?
    assert_raises(ActiveRecord::RecordNotDestroyed) { administrator.destroy! }
    assert_not administrator.delete_account!
    assert User.exists?(administrator.id)

    User.create!(email: "unverified-admin@example.com", administrator: true)
    assert_not administrator.update_administrator_role!(administrator: false), "an unverified administrator does not satisfy the invariant"
    assert administrator.reload.administrator?
  end

  test "a second verified administrator permits demotion and account deletion" do
    administrator = User.create!(email: "admin@example.com", verified_at: Time.current, administrator: true)
    User.create!(email: "second-admin@example.com", verified_at: Time.current, administrator: true)

    assert administrator.update_administrator_role!(administrator: false)
    assert_not administrator.reload.administrator?

    assert administrator.delete_account!
    assert_not User.exists?(administrator.id)
  end

  test "profile and operational fields reject oversized or unsupported input" do
    user = User.new(
      email: "builder@example.com",
      name: "n" * 101,
      testimonial: "t" * 2_001,
      slack_status: "arbitrary",
      clickfunnels_sync_status: "arbitrary",
      waitlist_rank: 0
    )

    assert_not user.valid?
    assert user.errors.of_kind?(:name, :too_long)
    assert user.errors.of_kind?(:testimonial, :too_long)
    assert user.errors.of_kind?(:slack_status, :inclusion)
    assert user.errors.of_kind?(:clickfunnels_sync_status, :inclusion)
    assert user.errors.of_kind?(:waitlist_rank, :greater_than)
  end

  test "avatar input rejects content outside the image allowlist" do
    user = User.new(email: "builder@example.com")
    user.avatar.attach(io: StringIO.new("<script>alert(1)</script>"), filename: "avatar.html", content_type: "text/html")

    assert_not user.valid?
    assert_includes user.errors[:avatar], "must be a PNG, JPEG, or WebP image"
  end
end
