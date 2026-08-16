require "test_helper"

class FacilitatorProfileReviewsTest < ActionDispatch::IntegrationTest
  setup do
    Program.create!(name: "Continuous", starts_on: Date.new(2026, 8, 20), ends_on: Date.new(2026, 12, 17), capacity: 10)
    @facilitator = User.create!(email: "facilitator@example.com", verified_at: Time.current, facilitator: true)
    @builder = User.create!(email: "builder@example.com", name: "Waiting Builder", verified_at: Time.current,
      enrollment_status: "waitlisted", waitlist_rank: 1, waitlist_joined_at: Time.current)
    @builder.products.create!(name: "Queue App", url: "https://queue.example", focus: true)
    @builder.update!(public_profile: true)
  end

  test "a facilitator can review, approve, and remove a public profile" do
    sign_in_as(@facilitator)

    get facilitator_profile_reviews_path
    assert_response :success
    assert_select "#builder-#{@builder.id}", text: /Waiting Builder/
    assert_includes response.body, "Queue App"

    patch facilitator_profile_review_path(@builder), params: { user: { public_profile_approved: "true" } }
    assert_redirected_to facilitator_profile_reviews_path(anchor: "builder-#{@builder.id}")
    assert @builder.reload.public_profile_approved?

    patch facilitator_profile_review_path(@builder), params: { user: { public_profile_approved: "false" } }
    assert_not @builder.reload.public_profile_approved?
  end

  test "a non-facilitator cannot review profiles" do
    sign_in_as(@builder)

    get facilitator_profile_reviews_path

    assert_redirected_to dashboard_path
  end

  private

  def sign_in_as(user)
    token = user.reload.generate_token_for(:email_verification)
    get verify_email_path(token: token)
    post verify_email_path, params: { token: token }
  end
end
