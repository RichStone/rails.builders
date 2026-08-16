require "test_helper"

class UserTest < ActiveSupport::TestCase
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

  test "opening the waitlist offers the first registered non-OG" do
    first = User.create!(email: "first@example.com")
    second = User.create!(email: "second@example.com")
    travel_to(Time.zone.local(2026, 8, 9, 10)) { first.complete_verification! }
    travel_to(Time.zone.local(2026, 8, 9, 11)) { second.complete_verification! }

    assert_equal [ first, second ], @program.ordered_waitlist.to_a

    @program.open_waitlist!

    assert_equal "offered", first.reload.enrollment_status
    assert_equal "offered", second.reload.enrollment_status
    assert_not @program.reload.og_priority?
  end

  test "a non-OG registering after the general waitlist opens is offered free capacity" do
    @program.update!(og_priority: false)
    user = User.create!(email: "new@example.com")

    user.complete_verification!

    assert user.reload.offered?
  end

  test "recipient confirms a current offer without completing a profile" do
    user = User.create!(email: "builder@example.com", og: true)
    user.complete_verification!

    assert user.accept_offer!
    assert_equal "active", user.reload.enrollment_status
    assert_nil user.name
    assert_not user.public_profile?
  end

  test "expired offer promotes the queue and requires explicit re-entry" do
    @program.update!(capacity: 1, og_priority: false)
    first = User.create!(email: "first@example.com")
    second = User.create!(email: "second@example.com")
    first.complete_verification!
    second.complete_verification!
    @program.promote_waitlist!

    travel_to(73.hours.from_now) { first.expire_offer! }

    assert_equal "expired", first.reload.enrollment_status
    assert_equal "offered", second.reload.enrollment_status

    first.opt_into_waitlist!

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

    active.destroy!

    assert waiting.reload.offered?
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
