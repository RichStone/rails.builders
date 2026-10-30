require "test_helper"

class CommunityStatisticsTest < ActionDispatch::IntegrationTest
  setup do
    Program.create!(name: "Continuous", starts_on: Date.new(2026, 9, 3), ends_on: Date.new(2026, 12, 17))
  end

  test "only first email confirmation counts and deleting an account preserves the total" do
    user = User.create!(email: "registrant@example.com")
    assert_equal 0, CommunityStatistic.current.registrants_count

    post verify_email_path, params: { token: user.generate_token_for(:email_verification) }
    assert_redirected_to dashboard_path
    assert_equal 1, CommunityStatistic.current.registrants_count
    post verify_email_path, params: { token: user.reload.generate_token_for(:email_verification) }
    assert_equal 1, CommunityStatistic.current.registrants_count

    assert user.reload.delete_account!
    assert_equal 1, CommunityStatistic.current.registrants_count
  end

  test "the public counters include only confirmed registrations since September" do
    User.create!(email: "early@example.com", verified_at: Time.utc(2026, 8, 31, 23, 59))
    User.create!(email: "confirmed@example.com", verified_at: Time.utc(2026, 9, 1))
    User.create!(email: "unconfirmed@example.com")
    User.transaction do
      User.create!(email: "rolled-back@example.com", verified_at: Time.current)
      raise ActiveRecord::Rollback
    end

    get root_path

    assert_response :success
    assert_select "#inactive-builders + #all-time-builders" do
      assert_select "h3", text: "All-time Builders"
      assert_select "dd", text: "6"
      assert_select "dd", text: "35"
      assert_select "dd", text: "1"
      assert_select "dt", text: "Registrants since the app launched in September 2026"
    end
    assert_select "#past-builders", count: 0
  end
end
