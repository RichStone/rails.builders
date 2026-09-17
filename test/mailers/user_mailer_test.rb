require "test_helper"

class UserMailerTest < ActionMailer::TestCase
  test "enrollment emails queued before opting out respect current preferences while sign-in still works" do
    user = User.create!(email: "builder@example.com", verified_at: Time.current, enrollment_status: "offered", offer_expires_at: 1.day.from_now)
    UserMailer.enrollment_status(user).deliver_later
    UserMailer.offer_reminder(user).deliver_later
    user.update!(enrollment_notifications: false)

    assert_no_emails { perform_enqueued_jobs }

    user.update!(enrollment_notifications: true, notifications_enabled: false)
    assert_no_emails do
      UserMailer.enrollment_status(user).deliver_now
      UserMailer.offer_reminder(user).deliver_now
    end
    assert_emails 1 do
      UserMailer.verification(user, "requested-link").deliver_now
    end
  end

  test "verification delivers the secure action in both parts" do
    user = User.create!(email: "builder@example.com")
    url = Rails.application.routes.url_helpers.verify_email_url(token: "verification-token", host: "example.com")
    home_url = Rails.application.routes.url_helpers.root_url(host: "example.com")
    privacy_url = Rails.application.routes.url_helpers.privacy_url(host: "example.com")
    terms_url = Rails.application.routes.url_helpers.terms_url(host: "example.com")

    mail = UserMailer.verification(user, "verification-token")

    assert_equal [ "builder@example.com" ], mail.to
    assert_equal "Your Rails Builders sign-in link", mail.subject
    assert_equal "multipart/alternative", mail.mime_type
    assert_includes mail.html_part.body.decoded, url
    assert_includes mail.text_part.body.decoded, url
    assert_includes mail.html_part.body.decoded, "If you didn’t request this link"
    assert_includes mail.text_part.body.decoded, "If you didn’t request this link"
    assert_includes mail.html_part.body.decoded, "mark yourself as an Active Builder"
    assert_includes mail.text_part.body.decoded, "mark yourself as an Active Builder"
    assert_includes mail.html_part.body.decoded, "join the waitlist"
    assert_includes mail.text_part.body.decoded, "join the waitlist"
    assert_match(/your turn is not confirmed/i, mail.html_part.body.decoded)
    assert_match(/your turn is not confirmed/i, mail.text_part.body.decoded)
    assert_includes mail.html_part.body.decoded, home_url
    assert_includes mail.text_part.body.decoded, home_url
    assert_includes mail.html_part.body.decoded, privacy_url
    assert_includes mail.text_part.body.decoded, privacy_url
    assert_includes mail.html_part.body.decoded, terms_url
    assert_includes mail.text_part.body.decoded, terms_url
    assert_includes mail.html_part.body.decoded, 'href="mailto:rich@looplabs.cc"'
    assert_includes mail.text_part.body.decoded, "Email us: rich@looplabs.cc"
  end

  test "verification does not repeat the readiness warning for an Active Builder" do
    user = User.create!(email: "active@example.com", verified_at: Time.current, enrollment_status: "active")

    mail = UserMailer.verification(user, "verification-token")

    assert_no_match(/your turn is not confirmed/i, mail.html_part.body.decoded)
    assert_no_match(/your turn is not confirmed/i, mail.text_part.body.decoded)
  end

  test "seat offer delivers the dashboard action in both parts" do
    user = User.create!(email: "builder@example.com", verified_at: Time.current, enrollment_status: "offered", offer_expires_at: 3.days.from_now)
    url = Rails.application.routes.url_helpers.dashboard_url(host: "example.com")

    mail = UserMailer.enrollment_status(user)

    assert_equal [ "builder@example.com" ], mail.to
    assert_equal "A Rails Builders seat is yours to confirm", mail.subject
    assert_match(/confirm your Seat within 72 hours/i, mail.html_part.body.decoded)
    assert_match(/confirm your Seat within 72 hours/i, mail.text_part.body.decoded)
    assert_includes mail.html_part.body.decoded, "complete the readiness checklist"
    assert_includes mail.text_part.body.decoded, "complete the readiness checklist"
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
    user = User.create!(email: "builder@example.com", verified_at: Time.current, enrollment_status: "waitlisted", waitlist_joined_at: Time.current, waitlist_rank: 1)
    url = Rails.application.routes.url_helpers.dashboard_url(host: "example.com")

    mail = UserMailer.enrollment_status(user)

    assert_equal [ "builder@example.com" ], mail.to
    assert_equal "You’re on the Rails Builders waitlist", mail.subject
    assert_includes mail.html_part.body.decoded, "#1"
    assert_includes mail.text_part.body.decoded, "#1"
    assert_includes mail.html_part.body.decoded, "We’ll email you when a Seat becomes available"
    assert_includes mail.text_part.body.decoded, "We’ll email you when a Seat becomes available"
    assert_includes mail.html_part.body.decoded, url
    assert_includes mail.text_part.body.decoded, url
  end

  test "waitlist outcome uses the same queue guidance for every builder" do
    Program.create!(name: "Continuous", starts_on: Date.new(2026, 8, 20), ends_on: Date.new(2026, 12, 17), capacity: 10)
    user = User.create!(email: "builder@example.com", verified_at: Time.current, enrollment_status: "waitlisted", waitlist_joined_at: Time.current, waitlist_rank: 1)

    mail = UserMailer.enrollment_status(user)

    assert_includes mail.html_part.body.decoded, "your turn arrives"
    assert_includes mail.text_part.body.decoded, "your turn arrives"
  end

  test "inactive outcome explains the readiness-gated waitlist opt-in" do
    user = User.create!(email: "builder@example.com", verified_at: Time.current, enrollment_status: "inactive")

    mail = UserMailer.enrollment_status(user)

    assert_equal "Your Rails Builders account is ready", mail.subject
    assert_includes mail.html_part.body.decoded, "complete the readiness checklist"
    assert_includes mail.text_part.body.decoded, "complete the readiness checklist"
    assert_includes mail.html_part.body.decoded, "not on the waitlist yet"
    assert_includes mail.text_part.body.decoded, "not on the waitlist yet"
  end

  test "confirmed outcome names Active Builder status in both parts" do
    program = Program.create!(name: "Continuous", starts_on: Date.new(2026, 9, 3), ends_on: Date.new(2026, 12, 17), capacity: 9)
    program.builder_sessions.create!(
      google_event_id: "next-session",
      title: "Rails Builders",
      scheduled_starts_at: Time.utc(2026, 9, 17, 15, 30),
      scheduled_ends_at: Time.utc(2026, 9, 17, 17, 0),
      time_zone: "Europe/Amsterdam"
    )
    user = User.create!(email: "builder@example.com", verified_at: Time.current, enrollment_status: "active")

    travel_to Time.utc(2026, 9, 13, 12) do
      mail = UserMailer.enrollment_status(user)

      assert_equal "Your Rails Builders seat is confirmed", mail.subject
      assert_includes mail.html_part.body.decoded, "officially an Active Builder"
      assert_includes mail.text_part.body.decoded, "officially an Active Builder"
      assert_includes mail.html_part.body.decoded, "Google Calendar invite"
      assert_includes mail.text_part.body.decoded, "Google Calendar invite"
      assert_includes mail.html_part.body.decoded, "Thursday, 17 September at 17:30 CEST"
      assert_includes mail.text_part.body.decoded, "Thursday, 17 September at 17:30 CEST"
      assert_includes mail.html_part.body.decoded, "Europe/Amsterdam"
      assert_includes mail.text_part.body.decoded, "Europe/Amsterdam"
    end
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
