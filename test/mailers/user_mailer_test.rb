require "test_helper"

class UserMailerTest < ActionMailer::TestCase
  test "verification delivers the secure action in both parts" do
    user = User.create!(email: "builder@example.com")
    url = Rails.application.routes.url_helpers.verify_email_url(token: "verification-token", host: "example.com")
    home_url = Rails.application.routes.url_helpers.root_url(host: "example.com")
    privacy_url = Rails.application.routes.url_helpers.privacy_url(host: "example.com")

    mail = UserMailer.verification(user, "verification-token")

    assert_equal [ "builder@example.com" ], mail.to
    assert_equal "Your Rails Builders sign-in link", mail.subject
    assert_equal "multipart/alternative", mail.mime_type
    assert_includes mail.html_part.body.decoded, url
    assert_includes mail.text_part.body.decoded, url
    assert_includes mail.html_part.body.decoded, "If you didn’t request this link"
    assert_includes mail.text_part.body.decoded, "If you didn’t request this link"
    assert_includes mail.html_part.body.decoded, home_url
    assert_includes mail.text_part.body.decoded, home_url
    assert_includes mail.html_part.body.decoded, privacy_url
    assert_includes mail.text_part.body.decoded, privacy_url
  end

  test "seat offer delivers the dashboard action in both parts" do
    user = User.create!(email: "builder@example.com", verified_at: Time.current, enrollment_status: "offered", offer_expires_at: 3.days.from_now)
    url = Rails.application.routes.url_helpers.dashboard_url(host: "example.com")

    mail = UserMailer.enrollment_status(user)

    assert_equal [ "builder@example.com" ], mail.to
    assert_equal "A Rails Builders seat is yours to confirm", mail.subject
    assert_match(/confirm your Seat within 72 hours/i, mail.html_part.body.decoded)
    assert_match(/confirm your Seat within 72 hours/i, mail.text_part.body.decoded)
    assert_includes mail.html_part.body.decoded, url
    assert_includes mail.text_part.body.decoded, url
  end

  test "offer reminder delivers the dashboard action in both parts" do
    user = User.create!(email: "builder@example.com", verified_at: Time.current, enrollment_status: "offered", offer_expires_at: 1.day.from_now)
    url = Rails.application.routes.url_helpers.dashboard_url(host: "example.com")

    mail = UserMailer.offer_reminder(user)

    assert_equal [ "builder@example.com" ], mail.to
    assert_equal "24 hours left to confirm your Rails Builders seat", mail.subject
    assert_includes mail.html_part.body.decoded, url
    assert_includes mail.text_part.body.decoded, url
  end

  test "offer reminder is suppressed after the Seat Offer ends" do
    user = User.create!(email: "builder@example.com", verified_at: Time.current, enrollment_status: "active")

    assert_instance_of ActionMailer::Base::NullMail, UserMailer.offer_reminder(user).message
  end

  test "newsletter confirmation keeps the optional action separate in both parts" do
    user = User.create!(email: "reader@example.com")
    url = Rails.application.routes.url_helpers.confirm_newsletter_url(token: "newsletter-token", host: "example.com")

    mail = UserMailer.newsletter_confirmation(user, "newsletter-token")

    assert_equal [ "reader@example.com" ], mail.to
    assert_equal "Confirm the Loop Labs newsletter", mail.subject
    assert_includes mail.html_part.body.decoded, url
    assert_includes mail.text_part.body.decoded, url
    assert_includes mail.html_part.body.decoded, "separate from your Rails Builders registration"
    assert_includes mail.text_part.body.decoded, "separate from your Rails Builders registration"
  end

  test "waitlist outcome explains the position" do
    Program.create!(name: "Continuous", starts_on: Date.new(2026, 8, 20), ends_on: Date.new(2026, 12, 17), capacity: 10)
    user = User.create!(email: "builder@example.com", verified_at: Time.current, enrollment_status: "waitlisted", waitlist_joined_at: Time.current, waitlist_rank: 1, og: true)
    url = Rails.application.routes.url_helpers.dashboard_url(host: "example.com")

    mail = UserMailer.enrollment_status(user)

    assert_equal [ "builder@example.com" ], mail.to
    assert_equal "You’re on the Rails Builders waitlist", mail.subject
    assert_includes mail.html_part.body.decoded, "#1"
    assert_includes mail.text_part.body.decoded, "#1"
    assert_includes mail.html_part.body.decoded, "All 10 seats are currently reserved"
    assert_includes mail.text_part.body.decoded, "All 10 seats are currently reserved"
    assert_includes mail.html_part.body.decoded, url
    assert_includes mail.text_part.body.decoded, url
  end

  test "general waitlist outcome explains OG Priority in both parts" do
    Program.create!(name: "Continuous", starts_on: Date.new(2026, 8, 20), ends_on: Date.new(2026, 12, 17), capacity: 10)
    user = User.create!(email: "builder@example.com", verified_at: Time.current, enrollment_status: "waitlisted", waitlist_joined_at: Time.current, waitlist_rank: 1)

    mail = UserMailer.enrollment_status(user)

    assert_includes mail.html_part.body.decoded, "Seats are currently in OG Priority"
    assert_includes mail.text_part.body.decoded, "Seats are currently in OG Priority"
  end

  test "confirmed outcome names Active Builder status in both parts" do
    user = User.create!(email: "builder@example.com", verified_at: Time.current, enrollment_status: "active")

    mail = UserMailer.enrollment_status(user)

    assert_equal "Your Rails Builders seat is confirmed", mail.subject
    assert_includes mail.html_part.body.decoded, "officially an Active Builder"
    assert_includes mail.text_part.body.decoded, "officially an Active Builder"
  end

  test "closed enrollment outcomes preserve their next-step guidance" do
    outcomes = {
      "declined" => [ "You declined your Rails Builders seat", "won’t be added back automatically" ],
      "expired" => [ "Your Rails Builders offer expired", "Seat has moved to the next builder" ],
      "withdrawn" => [ "Your Rails Builders seat was released", "place is open for the next builder" ],
      "unverified" => [ "Your Rails Builders status changed", "current status is Unverified" ]
    }
    user = User.create!(email: "builder@example.com")

    outcomes.each do |status, (subject, guidance)|
      mail = UserMailer.enrollment_status(user, status)

      assert_equal subject, mail.subject
      assert_includes mail.html_part.body.decoded, guidance
      assert_includes mail.text_part.body.decoded, guidance
    end
  end

  test "terminal enrollment outcomes explain re-entry eligibility" do
    user = User.create!(email: "builder@example.com", verified_at: Time.current, enrollment_status: "left_waitlist")

    left_mail = UserMailer.enrollment_status(user)
    assert_equal "You left the Rails Builders waitlist", left_mail.subject
    assert_includes left_mail.html_part.body.decoded, "join the end of the waitlist again"
    assert_includes left_mail.text_part.body.decoded, "join the end of the waitlist again"

    user.update!(enrollment_status: "removed")
    removed_mail = UserMailer.enrollment_status(user)
    assert_equal "Your Rails Builders enrollment was removed", removed_mail.subject
    assert_includes removed_mail.html_part.body.decoded, "Administrator must reinstate"
    assert_includes removed_mail.text_part.body.decoded, "Administrator must reinstate"
  end
end
