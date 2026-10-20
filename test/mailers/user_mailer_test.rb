require "test_helper"

class UserMailerTest < ActionMailer::TestCase
  test "session cancellation email is withheld while the session is still scheduled" do
    user = User.create!(email: "builder@example.com", name: "Casey", verified_at: Time.current, enrollment_status: "active")
    program = Program.create!(name: "Continuous", starts_on: Date.new(2026, 9, 3), ends_on: Date.new(2026, 12, 17))
    session = program.builder_sessions.create!(
      google_event_id: "cancellation-session", title: "Rails.Builders",
      scheduled_starts_at: Time.utc(2026, 10, 22, 15, 30), scheduled_ends_at: Time.utc(2026, 10, 22, 17, 0),
      time_zone: "Europe/Madrid"
    )

    assert_instance_of ActionMailer::Base::NullMail, UserMailer.session_cancellation(user, session).message
  end

  test "session cancellation email includes the reason latest promise next session and inline monster" do
    user, session = cancellation_email_records
    promise = cancellation_promise(user, session, at: Time.utc(2026, 10, 15, 15, 30), body: "Ship the tiny Rust app.")
    session.program.builder_sessions.create!(
      google_event_id: "no-promise-session", title: "Rails.Builders", state: "completed",
      scheduled_starts_at: Time.utc(2026, 10, 20, 15, 30), scheduled_ends_at: Time.utc(2026, 10, 20, 17, 0),
      time_zone: "Europe/Madrid"
    ).attendances.create!(user: user, display_name: "Casey", role: "builder", status: "present")
    following = session.program.builder_sessions.create!(
      google_event_id: "following-session", title: "Rails.Builders",
      scheduled_starts_at: Time.utc(2026, 10, 29, 16, 30), scheduled_ends_at: Time.utc(2026, 10, 29, 18, 0),
      time_zone: "Europe/Madrid"
    )

    travel_to Time.utc(2026, 10, 20, 10) do
      mail = UserMailer.session_cancellation(user, session).message

      assert_equal [ user.email ], mail.to
      assert_equal [ "rich@looplabs.cc" ], mail.reply_to
      assert_equal "22 Oct session canceled. Your side project approves.", mail.subject
      assert_equal({ idempotency_key: "session-cancellation-#{session.id}-#{user.id}" }, mail[:options].unparsed_value)
      [ mail.html_part.body.decoded, mail.text_part.body.decoded ].each do |body|
        assert_includes body, "Hey Casey"
        assert_includes body, "Thursday’s Rails Builders session (22 October) is canceled."
        assert_includes body, session.cancellation_reason
        assert_includes body, "You now have more time to work on what you promised:"
        assert_includes body, "Your last recorded promise · 15 October"
        assert_includes body, "Ship the tiny Rust app."
        assert_includes body, "http://example.com/sessions/#{promise.builder_session_id}"
        assert_includes body, "The Loop Monster is already arguing with the Rust compiler. He calls it progress."
        assert_includes body, "See you Thursday 29 October at 17:30 CET."
        assert_includes body, "http://example.com/sessions/#{following.id}"
        assert_includes body, "Configure your notifications"
      end
      image = mail.attachments["loop-monster-rust-mac.png"]
      assert image.inline?
      assert_equal "<loop-monster-rust-mac>", image.content_id
      html = Nokogiri::HTML(mail.html_part.body.decoded)
      assert_equal "cid:loop-monster-rust-mac", html.at_css("img")["src"]
      assert_includes html.at_css("img")["alt"], "Rust app on his MacBook"
    end
  end

  test "session cancellation uses only this recipient's retained prior promises in this program" do
    user, session = cancellation_email_records
    cancellation_promise(user, session, at: Time.utc(2026, 10, 1, 15, 30), body: "Retained promise.")
    deleted = cancellation_promise(user, session, at: Time.utc(2026, 10, 8, 15, 30), body: "Deleted promise.")
    deleted.builder_session.create_transcript!(state: "deleted", deleted_at: Time.current)
    cancellation_promise(user, session, at: Time.utc(2026, 10, 29, 16, 30), body: "Future promise.")
    other_program = Program.create!(name: "Other program", starts_on: Date.new(2026, 9, 3), ends_on: Date.new(2026, 12, 17))
    cancellation_promise(user, session, at: Time.utc(2026, 10, 15, 15, 30), body: "Other program promise.", program: other_program)
    other_user = User.create!(email: "another@example.com", verified_at: Time.current, enrollment_status: "active")
    cancellation_promise(other_user, session, at: Time.utc(2026, 10, 16, 15, 30), body: "Someone else's promise.")

    mail = UserMailer.session_cancellation(user, session).message

    [ mail.html_part.body.decoded, mail.text_part.body.decoded ].each do |body|
      assert_includes body, "Retained promise."
      [ "Deleted promise.", "Future promise.", "Other program promise.", "Someone else's promise." ].each do |private_copy|
        assert_not_includes body, private_copy
      end
    end
  end

  test "session cancellation has honest fallbacks and escapes the reason and promise" do
    user, session = cancellation_email_records
    mail = UserMailer.session_cancellation(user, session).message
    [ mail.html_part.body.decoded, mail.text_part.body.decoded ].each do |body|
      assert_includes body, "We don’t have a recorded promise for you yet"
      assert_includes body, "There isn’t another session scheduled yet."
      assert_not_includes body, "Your last recorded promise"
    end

    session.update!(cancellation_reason: "The <script>alert('reason')</script> appointment.")
    cancellation_promise(user, session, at: Time.utc(2026, 10, 15, 15, 30), body: "<script>alert('promise')</script>")
    mail = UserMailer.session_cancellation(user, session).message
    html = Nokogiri::HTML(mail.html_part.body.decoded)
    assert_empty html.css("script")
    assert_includes html.text, session.cancellation_reason
    assert_includes html.text, "<script>alert('promise')</script>"
  end

  test "session cancellation rechecks cancellation progress and current recipient eligibility" do
    user, session = cancellation_email_records
    session.update_columns(cancellation_calendar_deleted_at: nil)
    assert_instance_of ActionMailer::Base::NullMail, UserMailer.session_cancellation(user, session).message
    session.update_columns(cancellation_calendar_deleted_at: Time.current, cancellation_requested_at: nil)
    assert_instance_of ActionMailer::Base::NullMail, UserMailer.session_cancellation(user, session).message
    session.update_columns(cancellation_requested_at: Time.current)

    user.update_columns(notifications_enabled: false)
    assert_instance_of ActionMailer::Base::NullMail, UserMailer.session_cancellation(user, session).message
    user.update_columns(notifications_enabled: true, verified_at: nil)
    assert_instance_of ActionMailer::Base::NullMail, UserMailer.session_cancellation(user, session).message
    user.update_columns(verified_at: Time.current, enrollment_status: "removed")
    assert_instance_of ActionMailer::Base::NullMail, UserMailer.session_cancellation(user, session).message
    user.update_columns(enrollment_status: "inactive")
    assert_instance_of ActionMailer::Base::NullMail, UserMailer.session_cancellation(user, session).message
    user.update_columns(facilitator: true, session_reminders: false)
    assert_not_instance_of ActionMailer::Base::NullMail, UserMailer.session_cancellation(user, session).message
  end

  test "the strike-limit email embeds the sad monster above the copy and invites the Builder back" do
    user = User.create!(email: "builder@example.com", name: "Casey", verified_at: Time.current, enrollment_status: "inactive")
    attendance = BuilderSessionAttendance.new(id: 42, strike_absence_limit: 3, strike_inactivated_at: Time.utc(2026, 10, 16))
    mail = UserMailer.strike_limit_reached(user, attendance).message

    assert_equal [ user.email ], mail.to
    assert_equal [ "rich@looplabs.cc" ], mail.reply_to
    assert_equal({ idempotency_key: "strike-limit-42-1792108800" }, mail[:options].unparsed_value)
    [ mail.html_part.body.decoded, mail.text_part.body.decoded ].each do |body|
      assert_includes body, "Hey Casey"
      assert_includes body, "limit of 3 missed sessions in a row"
      assert_includes body, "marked you inactive"
      assert_includes body, "request to rejoin"
      assert_includes body, "you’re always welcome back"
      assert_includes body, "You’ll be added to the waitlist (if there is one) and we'll get you back in ASAP."
      assert_includes body, "http://example.com/dashboard"
    end
    image = mail.attachments["loop-monster-broken-rails.png"]
    assert image.inline?
    assert_equal "<loop-monster-broken-rails>", image.content_id
    html = Nokogiri::HTML(mail.html_part.body.decoded)
    assert_equal "cid:loop-monster-broken-rails", html.at_css("img")["src"]
    assert_operator mail.html_part.body.decoded.index("<img"), :<, mail.html_part.body.decoded.index("Life shipped a plot twist")

    user.update!(enrollment_notifications: false)
    assert_instance_of ActionMailer::Base::NullMail, UserMailer.strike_limit_reached(user, attendance).message
  end

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
    assert_equal "Your Rails.Builders sign-in link", mail.subject
    assert_equal "Rails.Builders", Mail::Address.new(mail[:from].decoded).display_name
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
    assert_equal "A Rails.Builders seat is yours to confirm", mail.subject
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
    assert_equal "24 hours left to confirm your Rails.Builders seat", mail.subject
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
    assert_includes mail.html_part.body.decoded, "separate from your Rails.Builders registration"
    assert_includes mail.text_part.body.decoded, "separate from your Rails.Builders registration"
  end

  test "waitlist outcome explains the position" do
    Program.create!(name: "Continuous", starts_on: Date.new(2026, 8, 20), ends_on: Date.new(2026, 12, 17), capacity: 10)
    user = User.create!(email: "builder@example.com", verified_at: Time.current, enrollment_status: "waitlisted", waitlist_joined_at: Time.current, waitlist_rank: 1)
    url = Rails.application.routes.url_helpers.dashboard_url(host: "example.com")

    mail = UserMailer.enrollment_status(user)

    assert_equal [ "builder@example.com" ], mail.to
    assert_equal "You’re on the Rails.Builders waitlist", mail.subject
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

    assert_equal "Your Rails.Builders account is ready", mail.subject
    assert_includes mail.html_part.body.decoded, "complete the readiness checklist"
    assert_includes mail.text_part.body.decoded, "complete the readiness checklist"
    assert_includes mail.html_part.body.decoded, "not on the waitlist yet"
    assert_includes mail.text_part.body.decoded, "not on the waitlist yet"
  end

  test "confirmed outcome names Active Builder status in both parts" do
    program = Program.create!(name: "Continuous", starts_on: Date.new(2026, 9, 3), ends_on: Date.new(2026, 12, 17), capacity: 9)
    program.builder_sessions.create!(
      google_event_id: "next-session",
      title: "Rails.Builders",
      scheduled_starts_at: Time.utc(2026, 9, 17, 15, 30),
      scheduled_ends_at: Time.utc(2026, 9, 17, 17, 0),
      time_zone: "Europe/Amsterdam"
    )
    user = User.create!(email: "builder@example.com", verified_at: Time.current, enrollment_status: "active")

    travel_to Time.utc(2026, 9, 13, 12) do
      mail = UserMailer.enrollment_status(user)

      assert_equal "Your Rails.Builders seat is confirmed", mail.subject
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
      "declined" => [ "You declined your Rails.Builders seat", "won’t be added back automatically" ],
      "expired" => [ "Your Rails.Builders offer expired", "Seat has moved to the next builder" ],
      "withdrawn" => [ "Your Rails.Builders seat was released", "place is open for the next builder" ],
      "unverified" => [ "Your Rails.Builders status changed", "current status is Unverified" ]
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
    assert_equal "You left the Rails.Builders waitlist", left_mail.subject
    assert_includes left_mail.html_part.body.decoded, "join the end of the waitlist again"
    assert_includes left_mail.text_part.body.decoded, "join the end of the waitlist again"

    user.update!(enrollment_status: "removed")
    removed_mail = UserMailer.enrollment_status(user)
    assert_equal "Your Rails.Builders enrollment was removed", removed_mail.subject
    assert_includes removed_mail.html_part.body.decoded, "Administrator must reinstate"
    assert_includes removed_mail.text_part.body.decoded, "Administrator must reinstate"
  end

  private

  def cancellation_email_records
    user = User.create!(email: "builder@example.com", name: "Casey Builder", verified_at: Time.current, enrollment_status: "active")
    program = Program.create!(name: "Continuous", starts_on: Date.new(2026, 9, 3), ends_on: Date.new(2026, 12, 17))
    session = program.builder_sessions.create!(
      google_event_id: "cancellation-session", title: "Rails.Builders", state: "cancelled",
      scheduled_starts_at: Time.utc(2026, 10, 22, 15, 30), scheduled_ends_at: Time.utc(2026, 10, 22, 17, 0),
      time_zone: "Europe/Madrid", cancellation_requested_at: Time.current, cancellation_calendar_deleted_at: Time.current,
      cancellation_reason: "Our facilitator has an appointment that cannot move."
    )
    [ user, session ]
  end

  def cancellation_promise(user, session, at:, body:, program: session.program)
    previous = program.builder_sessions.create!(
      google_event_id: "promise-session-#{user.id}-#{at.to_i}", title: "Rails.Builders", state: "completed",
      scheduled_starts_at: at, scheduled_ends_at: at + 90.minutes, time_zone: "Europe/Madrid"
    )
    previous.attendances.create!(user: user, display_name: user.name.presence || "Builder", role: "builder", status: "present")
    previous.next_session_promises.create!(user: user, body: body)
  end
end
