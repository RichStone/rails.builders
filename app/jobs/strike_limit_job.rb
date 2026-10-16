class StrikeLimitJob < ApplicationJob
  def perform
    program = Program.current
    User.active.where(facilitator: false).where.not(verified_at: nil).find_each do |user|
      release_at_limit(program, user)
    rescue StandardError => error
      Rails.error.report(error, context: { user_id: user.id })
    end

    BuilderSessionAttendance.where.not(strike_inactivated_at: nil).where.not(user_id: nil)
      .where("strike_email_sent_at IS NULL OR strike_calendar_removed_at IS NULL").find_each do |attendance|
      process_followups(attendance)
    end
  end

  private

  def release_at_limit(program, user)
    program.release_seat! do
      user.with_lock do
        next unless user.active? && !user.facilitator?

        sessions = program.builder_sessions.where(state: "completed", scheduled_starts_at: ..Time.current).order(:scheduled_starts_at, :id).to_a
        records = user.builder_session_attendances.where(builder_session_id: sessions.map(&:id)).index_by(&:builder_session_id)
        streak = BuilderSessionAttendance.absence_streak(sessions:, attendances: records, reset_at: user.attendance_streak_reset_at)
        next unless streak.size >= program.consecutive_absence_limit

        streak.first.update!(strike_inactivated_at: Time.current, strike_absence_limit: program.consecutive_absence_limit, strike_email_sent_at: nil)
        user.strike_limit_release = true
        user.update!(enrollment_status: "inactive", offer_expires_at: nil, waitlist_joined_at: nil, waitlist_rank: nil)
        [ true, true ]
      end
    end
  end

  def process_followups(attendance)
    claim = attendance.with_lock do
      next unless followup_user(attendance)
      next if attendance.strike_followups_claimed_at && attendance.strike_followups_claimed_at > 10.minutes.ago

      claimed_at = Time.current
      attendance.update!(strike_followups_claimed_at: claimed_at)
      claimed_at
    end
    return unless claim

    claimed_record = BuilderSessionAttendance.where(id: attendance.id, strike_followups_claimed_at: claim)
    deliver_email(attendance, claimed_record)
    remove_calendar_invites(attendance, claimed_record)
  rescue StandardError => error
    Rails.error.report(error, context: { attendance_id: attendance.id })
  ensure
    claimed_record&.update_all(strike_followups_claimed_at: nil)
  end

  def followup_user(attendance)
    user = User.find_by(id: attendance.user_id)
    return if !user || user.active? || user.facilitator? || user.removed?
    return if user.attendance_streak_reset_at && user.attendance_streak_reset_at >= attendance.strike_inactivated_at

    user
  end

  def deliver_email(attendance, claimed_record)
    user = followup_user(attendance)
    return unless user
    return if attendance.strike_email_sent_at? || !user.receives_enrollment_notifications?

    message = UserMailer.strike_limit_reached(user, attendance).deliver_now
    claimed_record.update_all(strike_email_sent_at: Time.current) if message
  rescue StandardError => error
    Rails.error.report(error, context: { attendance_id: attendance.id })
  end

  def remove_calendar_invites(attendance, claimed_record)
    user = followup_user(attendance)
    return unless user
    return if attendance.strike_calendar_removed_at?

    connection = attendance.builder_session.program.calendar_connection
    return unless connection && connection.status.in?(%w[connected error])

    program = connection.program
    if Time.current < program.countdown_ends_at
      removal_attempted = true
      client_for(connection).remove_attendee_from_upcoming_events(
        calendar_id: connection.google_calendar_id, starts_at: Time.current,
        ends_at: program.countdown_ends_at, email: user.email
      )
    end
    claimed_record.update_all(strike_calendar_removed_at: Time.current)
  rescue GoogleWorkspace::AuthorizationRequired, Google::Apis::AuthorizationError, Signet::AuthorizationError => error
    connection.update!(status: "reauthorization_required", last_error_code: error.class.name.first(100))
    Rails.error.report(error, context: { attendance_id: attendance.id })
  rescue StandardError => error
    Rails.error.report(error, context: { attendance_id: attendance.id })
  ensure
    # Earlier patches may have succeeded before a later one failed.
    if removal_attempted && User.exists?(id: user.id, enrollment_status: "active")
      GoogleCalendarAttendeeJob.perform_later(connection.id, user.id, false)
    end
  end

  def client_for(connection)
    GoogleWorkspace::CalendarClient.new(connection:)
  end
end
