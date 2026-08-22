require "test_helper"

class EnrollmentActionsTest < ActionDispatch::IntegrationTest
  setup do
    Program.create!(name: "Continuous", starts_on: Date.new(2026, 8, 20), ends_on: Date.new(2026, 12, 17), capacity: 10, og_priority: false)
  end

  test "builder can accept, withdraw, and explicitly rejoin" do
    user = User.create!(email: "builder@example.com", verified_at: Time.current, enrollment_status: "offered", offer_expires_at: 2.days.from_now)
    sign_in_as(user)

    post accept_offer_path
    assert user.reload.active?

    post withdraw_seat_path
    assert_equal "withdrawn", user.reload.enrollment_status

    post join_waitlist_path
    assert user.reload.offered?, "open capacity should immediately offer the newly joined builder"
  end

  test "builder can decline without being silently re-added" do
    user = User.create!(email: "builder@example.com", verified_at: Time.current, enrollment_status: "offered", offer_expires_at: 2.days.from_now)
    sign_in_as(user)

    post decline_offer_path

    assert_equal "declined", user.reload.enrollment_status
    assert_nil user.waitlist_joined_at
  end

  test "active membership switch only permits withdrawal" do
    user = User.create!(email: "builder@example.com", verified_at: Time.current, enrollment_status: "active", slack_desired_state: "present")
    sign_in_as(user)

    get dashboard_path
    assert_select "label", text: /Active membership/
    assert_select "input[name='active'][checked]"

    patch membership_path, params: { active: "0" }
    assert_redirected_to dashboard_path
    assert_equal "withdrawn", user.reload.enrollment_status
    assert_equal "absent", user.slack_desired_state

    patch membership_path, params: { active: "1" }
    assert_equal "withdrawn", user.reload.enrollment_status

    get dashboard_path
    assert_select "input[name='active'][disabled]:not([checked])"
  end

  test "eligible builder can switch waitlist participation on and off" do
    Program.current.update!(capacity: 1)
    User.create!(email: "active@example.com", verified_at: Time.current, enrollment_status: "active")
    user = User.create!(email: "builder@example.com", verified_at: Time.current, enrollment_status: "withdrawn")
    sign_in_as(user)

    get dashboard_path
    assert_select "label", text: /Join the waitlist/
    assert_select "input[name='joined']:not([checked])"

    patch waitlist_path, params: { joined: "1" }
    assert_redirected_to dashboard_path
    assert user.reload.waitlisted?

    get dashboard_path
    assert_select "input[name='joined'][checked]"

    patch waitlist_path, params: { joined: "0" }
    assert_equal "left_waitlist", user.reload.enrollment_status
    assert_nil user.waitlist_joined_at
    assert_nil user.waitlist_rank

    patch waitlist_path, params: { joined: "0" }
    assert_equal "left_waitlist", user.reload.enrollment_status
  end

  test "dashboard presents terminal states and keeps explicit Seat Offer actions" do
    user = User.create!(email: "builder@example.com", verified_at: Time.current, enrollment_status: "left_waitlist")
    sign_in_as(user)

    get dashboard_path
    assert_select "h1", text: "You left the waitlist."
    assert_select ".status-pill", text: "Left waitlist"

    user.update!(enrollment_status: "removed")
    get dashboard_path
    assert_select "h1", text: "Your enrollment was removed."
    assert_select "label", text: /Join the waitlist/, count: 0

    user.update!(enrollment_status: "offered", offer_expires_at: 2.days.from_now)
    get dashboard_path
    assert_select "form[action='#{accept_offer_path}']", text: /Accept/
    assert_select "form[action='#{decline_offer_path}']", text: /Decline/
  end

  private

  def sign_in_as(user)
    token = user.reload.generate_token_for(:email_verification)
    get verify_email_path(token: token)
    post verify_email_path, params: { token: token }
  end
end
