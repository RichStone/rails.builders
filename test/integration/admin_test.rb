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

  test "admin can open general waitlist and update builder roles" do
    sign_in_as(@admin)
    get admin_root_path
    assert_response :success
    assert_select "tr", text: /Registrant/
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
