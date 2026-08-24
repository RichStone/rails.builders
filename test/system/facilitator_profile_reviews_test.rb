require "application_system_test_case"

class FacilitatorProfileReviewsSystemTest < ApplicationSystemTestCase
  setup do
    Program.create!(name: "Continuous", starts_on: Date.current, ends_on: 4.months.from_now.to_date, capacity: 10)
    @facilitator = User.create!(email: "facilitator@example.com", verified_at: Time.current, facilitator: true)
    @builder = User.create!(
      email: "builder@example.com",
      name: "Approved Builder",
      verified_at: Time.current,
      enrollment_status: "active"
    )
    @builder.products.create!(name: "Queue App", url: "https://queue.example", focus: true)
    @builder.update!(public_profile: true, public_profile_approved: true)
  end

  test "remove approval text stays readable on mobile" do
    page.current_window.resize_to(390, 844)
    sign_in_as(@facilitator)

    visit facilitator_profile_reviews_path

    button = find_button("Remove approval")
    assert_equal "rgb(36, 24, 26)", page.evaluate_script("getComputedStyle(arguments[0]).color", button)
  end

  private

  def sign_in_as(user)
    visit verify_email_path(token: user.reload.generate_token_for(:email_verification))
    click_button "Sign in"
    assert_text "Profile publication"
  end
end
