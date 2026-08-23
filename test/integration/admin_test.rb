require "test_helper"

class AdminTest < ActionDispatch::IntegrationTest
  setup do
    @program = Program.create!(name: "Continuous", starts_on: Date.new(2026, 8, 20), ends_on: Date.new(2026, 12, 17), capacity: 10)
    @admin = User.create!(email: "admin@example.com", verified_at: Time.current, administrator: true)
    @builder = User.create!(email: "builder@example.com", verified_at: Time.current, enrollment_status: "waitlisted", waitlist_rank: 1, waitlist_joined_at: Time.current)
  end

  test "non-admins cannot enter admin" do
    sign_in_as(@builder)
    get admin_root_path
    assert_redirected_to dashboard_path
  end

  test "Calendar connection leaves Turbo so the browser can follow Google redirects" do
    sign_in_as(@admin)

    get admin_root_path

    assert_select "form[action='#{admin_calendar_connection_path}'][data-turbo='false'] button",
      text: "Connect Google Calendar"
    assert_equal "same-origin", response.headers["Referrer-Policy"]
    assert_includes response.headers.fetch("Content-Security-Policy"),
      "form-action 'self' https://accounts.google.com"
  end

  test "admin explains how pausing waitlist promotion works" do
    sign_in_as(@admin)

    get admin_root_path

    assert_select ".admin-check-with-help" do
      assert_select "label.check-row", text: /Pause waitlist promotion/
      assert_select "details.info-tip:not([open])" do
        assert_select "summary[aria-label='About pausing waitlist promotion']", text: "?"
        assert_select "p", text: /Existing offers and confirmed seats are unchanged/
      end
    end
  end

  test "admin can open general waitlist and update builder roles" do
    sign_in_as(@admin)
    get admin_root_path
    assert_response :success
    assert_select ".admin-builder-card", text: /Registrant/
    assert_not_includes response.body, "false, false"

    patch admin_program_path(@program), params: { program: { og_priority: "0", capacity: 10 } }
    assert_not @program.reload.og_priority?
    assert_equal "offered", @builder.reload.enrollment_status

    patch admin_user_path(@builder), params: { user: { facilitator: "1", slack_status: "invited" } }
    post grant_administrator_admin_user_path(@builder)
    assert @builder.reload.facilitator?
    assert @builder.administrator?
    assert_equal "invited", @builder.slack_status
  end

  test "admin assigns the Program main facilitator from facilitator-role users" do
    @builder.update!(facilitator: true)
    sign_in_as(@admin)

    patch admin_program_path(@program), params: { program: { main_facilitator_id: @builder.id } }

    assert_redirected_to admin_root_path
    assert_equal @builder, @program.reload.main_facilitator
  end

  test "admin can edit the ordered Program format points" do
    sign_in_as(@admin)

    patch admin_program_path(@program), params: { program: { format_points: "🚂 First stop\n🤝 Last stop" } }

    assert_redirected_to admin_root_path
    assert_equal [ "🚂 First stop", "🤝 Last stop" ], @program.reload.format_points_list
  end

  test "admin can edit the ordered Program readiness points" do
    sign_in_as(@admin)

    patch admin_program_path(@program), params: { program: { readiness_points: "One product\nOne checkout" } }

    assert_redirected_to admin_root_path
    assert_equal [ "One product", "One checkout" ], @program.reload.readiness_points_list
  end

  test "admin groups Builders into OG and waitlist sections" do
    User.create!(email: "og@example.com", og: true)
    sign_in_as(@admin)

    get admin_root_path

    assert_select "h2", text: "Builders"
    assert_select "[data-builder-group='og'] .admin-builder-card", text: /og@example.com/
    assert_select "[data-builder-group='waitlist'] .admin-builder-card", text: /builder@example.com/
  end

  test "changing the main facilitator disconnects the old Calendar but keeps the schedule until reconnection" do
    old_facilitator = User.create!(email: "old-facilitator@example.com", facilitator: true, verified_at: Time.current)
    @builder.update!(facilitator: true)
    @program.update!(main_facilitator: old_facilitator)
    connection = @program.create_calendar_connection!(
      facilitator: old_facilitator,
      google_account_email: old_facilitator.email,
      google_calendar_id: "old-calendar",
      google_calendar_name: "Old Sessions",
      oauth_token_json: "{}"
    )
    upcoming = @program.builder_sessions.create!(
      google_event_id: "old-event",
      title: "Old recurring session",
      scheduled_starts_at: 2.days.from_now,
      scheduled_ends_at: 2.days.from_now + 1.hour,
      time_zone: "Europe/Madrid"
    )
    sign_in_as(@admin)

    fake_authorization = Object.new
    fake_authorization.define_singleton_method(:revoke!) { true }
    with_stubbed_singleton_method(GoogleWorkspace::Authorization, :new, ->(**) { fake_authorization }) do
      patch admin_program_path(@program), params: { program: { main_facilitator_id: @builder.id } }
    end

    assert_redirected_to admin_root_path
    assert_not ProgramCalendarConnection.exists?(connection.id)
    assert_equal "ready", upcoming.reload.state
    assert_equal @builder, upcoming.assigned_facilitator
    assert_nil upcoming.meet_url
  end

  test "changing the main facilitator waits for automatic transcript import" do
    old_facilitator = User.create!(email: "old-facilitator@example.com", facilitator: true, verified_at: Time.current)
    @builder.update!(facilitator: true)
    @program.update!(main_facilitator: old_facilitator)
    connection = @program.create_calendar_connection!(
      facilitator: old_facilitator,
      google_account_email: old_facilitator.email,
      google_calendar_id: "old-calendar",
      google_calendar_name: "Old Sessions",
      oauth_token_json: "{}"
    )
    builder_session = @program.builder_sessions.create!(
      google_event_id: "just-finished",
      title: "Just finished",
      meet_url: "https://meet.google.com/abc-defg-hij",
      scheduled_starts_at: 1.hour.ago,
      scheduled_ends_at: Time.current,
      time_zone: "Europe/Madrid"
    )
    travel_to 25.hours.ago do
      builder_session.start!(facilitator: old_facilitator)
      builder_session.finish!
    end
    sign_in_as(@admin)

    patch admin_program_path(@program), params: { program: { main_facilitator_id: @builder.id } }

    assert_redirected_to admin_root_path
    assert_equal old_facilitator, @program.reload.main_facilitator
    assert ProgramCalendarConnection.exists?(connection.id)
    assert_equal "pending", builder_session.transcript.reload.state
  end

  test "admin profile changes require fresh facilitator approval" do
    @builder.update!(name: "Waiting Builder")
    @builder.products.create!(name: "Queue App", url: "https://queue.example", focus: true)
    @builder.update!(public_profile: true, public_profile_approved: true)
    sign_in_as(@admin)

    patch admin_user_path(@builder), params: { user: { testimonial: "Updated by an administrator" } }

    assert_not @builder.reload.public_profile_approved?
  end

  test "admin uses named removal and reinstatement actions instead of raw status editing" do
    @program.update!(capacity: 1, og_priority: false)
    @builder.update!(enrollment_status: "active", slack_desired_state: "present", waitlist_rank: nil, waitlist_joined_at: nil)
    waiting = User.create!(email: "waiting@example.com", verified_at: Time.current, enrollment_status: "waitlisted", waitlist_rank: 1, waitlist_joined_at: Time.current)
    sign_in_as(@admin)

    get edit_admin_user_path(@builder)
    assert_select "select[name='user[enrollment_status]']", count: 0
    assert_select "form[action='#{remove_admin_user_path(@builder)}']", text: /Remove from Rails Builders/

    post remove_admin_user_path(@builder)
    assert_redirected_to edit_admin_user_path(@builder)
    assert_equal "removed", @builder.reload.enrollment_status
    assert_equal "absent", @builder.slack_desired_state
    assert waiting.reload.offered?

    get admin_root_path
    assert_select ".status-pill", text: "Removed", minimum: 1

    post remove_admin_user_path(@builder)
    assert_equal "removed", @builder.reload.enrollment_status

    patch admin_user_path(@builder), params: { user: { enrollment_status: "active" } }
    assert_equal "removed", @builder.reload.enrollment_status

    get edit_admin_user_path(@builder)
    assert_select "form[action='#{reinstate_admin_user_path(@builder)}']", text: /Reinstate enrollment eligibility/

    post reinstate_admin_user_path(@builder)
    assert_equal "left_waitlist", @builder.reload.enrollment_status
    assert_not @builder.offered?

    get admin_root_path
    assert_select ".status-pill", text: "Left waitlist", minimum: 1
  end

  test "last verified Administrator is protected while Facilitator remains independent" do
    @admin.update!(facilitator: true)
    sign_in_as(@admin)

    post revoke_administrator_admin_user_path(@admin)
    assert_redirected_to edit_admin_user_path(@admin)
    assert @admin.reload.administrator?
    assert @admin.facilitator?

    User.create!(email: "second-admin@example.com", verified_at: Time.current, administrator: true)
    post revoke_administrator_admin_user_path(@admin)
    assert_not @admin.reload.administrator?
    assert @admin.facilitator?
  end

  test "Administrator account deletion preserves the last verified Administrator" do
    sign_in_as(@admin)

    delete admin_user_path(@admin)
    assert_redirected_to edit_admin_user_path(@admin)
    assert User.exists?(@admin.id)

    User.create!(email: "second-admin@example.com", verified_at: Time.current, administrator: true)
    delete admin_user_path(@admin)
    assert_redirected_to admin_root_path
    assert_not User.exists?(@admin.id)
  end

  private

  def sign_in_as(user)
    token = user.reload.generate_token_for(:email_verification)
    get verify_email_path(token: token)
    post verify_email_path, params: { token: token }
  end
end
