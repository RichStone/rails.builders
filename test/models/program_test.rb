require "test_helper"

class ProgramTest < ActiveSupport::TestCase
  setup do
    @program = Program.create!(name: "Continuous", starts_on: Date.new(2026, 8, 20), ends_on: Date.new(2026, 12, 17), capacity: 1, og_priority: false)
  end

  test "a facilitator never consumes a seat" do
    User.create!(email: "facilitator@example.com", facilitator: true, enrollment_status: "active", verified_at: Time.current)
    assert_equal 0, @program.occupied_seats
    assert @program.seat_available?
  end

  test "places left reflects seats that builders have reserved" do
    @program.update!(capacity: 3)
    User.create!(email: "active@example.com", enrollment_status: "active", verified_at: Time.current)
    User.create!(email: "offered@example.com", enrollment_status: "offered", offer_expires_at: 1.day.from_now, verified_at: Time.current)

    assert_equal 1, @program.places_left
  end

  test "the session format is stored as an ordered list on the Program" do
    assert_equal "🚂 Forever free & community-led", @program.format_points_list.first
    assert_equal 9, @program.format_points_list.size
  end

  test "the readiness checklist is stored as an ordered list on the Program" do
    assert_equal "You have the ONE product you would hack on with us.", @program.readiness_points_list.first
    assert_equal "You have a checkout (so it's purchaseable).", @program.readiness_points_list.last
    assert_equal 6, @program.readiness_points_list.size
  end

  test "the readiness confirmation requires every current Program point" do
    @program.update!(readiness_points: "One product\nOne checkout")

    assert @program.readiness_confirmed?(%w[0 1])
    assert_not @program.readiness_confirmed?(%w[0])
    assert_not @program.readiness_confirmed?(%w[0 1 2])
  end

  test "paused promotions leave capacity open until resumed" do
    builder = User.create!(email: "builder@example.com", verified_at: Time.current, enrollment_status: "waitlisted", waitlist_joined_at: Time.current, waitlist_rank: 1)
    @program.update!(promotions_paused: true)

    @program.promote_waitlist!
    assert builder.reload.waitlisted?

    @program.update!(promotions_paused: false)
    @program.promote_waitlist!
    assert builder.reload.offered?
  end

  test "lowering capacity does not revoke confirmed seats" do
    first = User.create!(email: "first@example.com", verified_at: Time.current, enrollment_status: "active")
    second = User.create!(email: "second@example.com", verified_at: Time.current, enrollment_status: "active")

    @program.update!(capacity: 1)

    assert first.reload.active?
    assert second.reload.active?
    assert_not @program.seat_available?
  end

  test "program input rejects an end date before its start date" do
    @program.assign_attributes(starts_on: Date.new(2026, 8, 20), ends_on: Date.new(2026, 8, 19))

    assert_not @program.valid?
    assert @program.errors.of_kind?(:ends_on, :after_or_equal_to)
  end

  test "program name input is normalized before validation" do
    @program.name = "  Continuous  "

    assert @program.valid?
    assert_equal "Continuous", @program.name
  end
end
