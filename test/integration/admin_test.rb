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

    patch admin_user_path(@builder), params: { user: { facilitator: "1", administrator: "1", slack_status: "invited" } }
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

  private

  def sign_in_as(user)
    token = user.reload.generate_token_for(:email_verification)
    get verify_email_path(token: token)
    post verify_email_path, params: { token: token }
  end
end
