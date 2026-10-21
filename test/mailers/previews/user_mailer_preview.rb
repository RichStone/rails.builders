class UserMailerPreview < ActionMailer::Preview
  def verification
    UserMailer.verification(preview_user, "preview-verification-token")
  end

  def newsletter_confirmation
    UserMailer.newsletter_confirmation(preview_user, "preview-newsletter-token")
  end

  def confirmed_seat
    UserMailer.enrollment_status(preview_user, "active")
  end

  def strike_limit_reached
    user = User.new(email: "builder@example.com", name: "Casey", enrollment_status: "inactive")
    attendance = BuilderSessionAttendance.new(strike_absence_limit: 3, strike_inactivated_at: Time.utc(2026, 10, 16))
    UserMailer.strike_limit_reached(user, attendance)
  end

  def session_cancellation
    user = User.new(email: "builder@example.com", name: "Casey", enrollment_status: "active", verified_at: Time.current)
    program = Program.new(name: "Continuous")
    session = program.builder_sessions.build(
      state: "cancelled", title: "Rails.Builders", time_zone: "Europe/Madrid",
      scheduled_starts_at: 2.days.from_now, scheduled_ends_at: 2.days.from_now + 90.minutes,
      cancellation_requested_at: Time.current, cancellation_calendar_deleted_at: Time.current,
      cancellation_reason: "Rich has an important appointment he can’t miss."
    )
    UserMailer.session_cancellation(user, session)
  end

  private

  def preview_user
    User.new(email: "builder@example.com", og: true)
  end
end
