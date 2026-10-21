require "test_helper"

class EnrollmentActionsTest < ActionDispatch::IntegrationTest
  setup do
    Program.create!(name: "Continuous", starts_on: Date.new(2026, 8, 20), ends_on: Date.new(2026, 12, 17), capacity: 10)
  end

  test "builders wait for staff approval and gain the next session link only after activation" do
    facilitator = User.create!(email: "facilitator@example.com", verified_at: Time.current, facilitator: true)
    Program.current.update!(main_facilitator: facilitator)
    connection = Program.current.create_calendar_connection!(
      facilitator:,
      google_account_email: facilitator.email,
      google_calendar_id: "sessions@group.calendar.google.com",
      google_calendar_name: "Rails.Builders Sessions",
      oauth_token_json: "{}",
      status: "connected"
    )
    upcoming = Program.current.builder_sessions.create!(
      google_event_id: "next-session", title: "Next build",
      scheduled_starts_at: 1.day.from_now, scheduled_ends_at: 1.day.from_now + 90.minutes,
      meet_url: "https://meet.google.com/abc-defg-hij", time_zone: "Europe/Madrid"
    )
    user = User.create!(email: "ready@example.com", verified_at: Time.current, enrollment_status: "offered", offer_expires_at: 2.days.from_now)
    sign_in_as(user)

    get dashboard_path
    assert_select "input[name='readiness[]']", count: 0
    assert_select "form[action='#{membership_path}']", count: 0
    assert_select "main", text: /a few days at most/
    assert_select ".dashboard-next-steps li", count: 3
    assert_select ".dashboard-next-steps li", text: /Join the next session/
    assert_select "a[href='#{join_builder_session_path(upcoming)}']", count: 0
    assert_no_match "meet.google.com", response.body
    get join_builder_session_path(upcoming)
    assert_redirected_to dashboard_path

    patch membership_path, params: { active: "1", readiness: %w[0 1 2 3 4 5] }
    assert_redirected_to dashboard_path
    assert user.reload.offered?, "a builder must not be able to approve their own seat"

    sign_in_as(facilitator)
    get builder_path(user)
    assert_select "input[name='send_calendar_notification'][checked]"
    assert_enqueued_with(job: GoogleCalendarAttendeeJob, args: [ connection.id, user.id, true ]) do
      post promote_builder_path(user)
    end
    assert user.reload.active?

    sign_in_as(user)
    get dashboard_path
    assert_select ".dashboard-next-steps li", count: 3
    assert_select "a[href='#{join_builder_session_path(upcoming)}']", text: "Join the next session"
    get join_builder_session_path(upcoming)
    assert_redirected_to "https://meet.google.com/abc-defg-hij"
  end

  test "builder can withdraw and explicitly request to rejoin" do
    user = User.create!(email: "builder@example.com", verified_at: Time.current, enrollment_status: "active")
    sign_in_as(user)

    post withdraw_seat_path
    assert_equal "withdrawn", user.reload.enrollment_status

    patch waitlist_path, params: { joined: "1", readiness: %w[0 1 2 3 4 5] }
    assert user.reload.offered?, "open capacity should immediately offer the newly joined builder"
    assert_redirected_to dashboard_path
    follow_redirect!
    assert_select ".flash", text: /a few days at most/
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
    assert_select "label", text: /I’m an Active Builder/
    assert_select "label", text: /joining the live sessions consistently/
    assert_select "input[name='active'][checked]"
    assert_select "dialog", text: /Hang up your hard hat\?/
    assert_select "dialog", text: /return to civilian life.*great exit instead/
    assert_select "button", text: "Keep me building"
    assert_select "button", text: "Leave Active Builders"
    assert_select "input[type='submit']", text: /Update membership/, count: 0

    patch membership_path, params: { active: "0" }
    assert_redirected_to dashboard_path
    assert_equal "withdrawn", user.reload.enrollment_status
    assert_equal "absent", user.slack_desired_state

    patch membership_path, params: { active: "1" }
    assert_equal "withdrawn", user.reload.enrollment_status

    get dashboard_path
    assert_select "input[name='active']", count: 0
  end

  test "eligible builder can switch waitlist participation on and off" do
    Program.current.update!(capacity: 1)
    User.create!(email: "active@example.com", verified_at: Time.current, enrollment_status: "active")
    user = User.create!(email: "builder@example.com", verified_at: Time.current, enrollment_status: "withdrawn")
    sign_in_as(user)

    get dashboard_path
    assert_select "[data-waitlist-readiness] [data-readiness-checklist-target='activation'][hidden]"
    assert_select "[data-waitlist-readiness] h3", text: "The readiness checklist"
    assert_select "[data-waitlist-readiness] .readiness-promise", text: "Confirm the readiness promise to take your seat. Please check your email! 📧"
    assert_select "[data-waitlist-readiness] .membership-readiness > p", text: /shared ingredients behind the live sessions.*Join Builders/
    assert_select "input[name='readiness[]']", count: 6

    patch waitlist_path, params: { joined: "1" }
    assert_redirected_to dashboard_path
    assert_equal "withdrawn", user.reload.enrollment_status

    patch waitlist_path, params: { joined: "1", readiness: %w[0 1 2 3 4 5] }
    assert_redirected_to dashboard_path
    assert user.reload.waitlisted?

    get dashboard_path
    assert_select "input[name='joined'][checked]"
    assert_select "input[name='readiness[]']", count: 0
    assert_select "figure figcaption", text: "The Loop Monster is waiting with you"
    assert_select "figure img[alt*='watch']"
    assert_select ".dashboard-next-steps h2", text: "Next: make your public profile"
    assert_select ".dashboard-next-steps li.is-complete", count: 1
    assert_select ".dashboard-next-steps li.is-next a[href='#{edit_profile_path}']"
    assert_select "dialog", text: /Give up your spot\?/
    assert_select "dialog", text: /lose position #1.*but I was here before/
    assert_select "button", text: "Keep my spot"
    assert_select "button", text: "Leave the waitlist"
    assert_select "input[type='submit']", text: /Update waitlist/, count: 0

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
    assert_select "form[action='#{membership_path}']", count: 0
    assert_select "input[name='readiness[]']", count: 0
    assert_select "form", text: /Accept Seat Offer/, count: 0
    assert_select "form[action='#{decline_offer_path}']", text: "Cancel my request"
  end

  private

  def sign_in_as(user)
    token = user.reload.generate_token_for(:email_verification)
    get verify_email_path(token: token)
    post verify_email_path, params: { token: token }
  end
end
