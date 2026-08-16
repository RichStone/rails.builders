require "test_helper"

class UserMailerTest < ActionMailer::TestCase
  test "waitlist outcome explains the position" do
    Program.create!(name: "Continuous", starts_on: Date.new(2026, 8, 20), ends_on: Date.new(2026, 12, 17), capacity: 10)
    user = User.create!(email: "builder@example.com", verified_at: Time.current, enrollment_status: "waitlisted", waitlist_joined_at: Time.current, waitlist_rank: 1)

    mail = UserMailer.enrollment_status(user)

    assert_equal [ "builder@example.com" ], mail.to
    assert_equal "You’re on the Rails Builders waitlist", mail.subject
    assert_match "#1", mail.body.encoded
  end
end
