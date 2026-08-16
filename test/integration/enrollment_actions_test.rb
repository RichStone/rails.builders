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

  private

  def sign_in_as(user)
    token = user.reload.generate_token_for(:email_verification)
    get verify_email_path(token: token)
    post verify_email_path, params: { token: token }
  end
end
