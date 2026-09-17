class SessionReminderJob < ApplicationJob
  def perform
    BuilderSession.where(state: "ready", scheduled_starts_at: Time.current..168.hours.from_now).find_each do |builder_session|
      reminders = User.active.or(User.where(facilitator: true)).filter_map do |user|
        next unless user.session_reminder_due?(builder_session)

        reminder = SessionReminder.create_or_find_by!(user: user, builder_session: builder_session, scheduled_starts_at: builder_session.scheduled_starts_at)
        reminder unless reminder.processed?
      rescue StandardError => error
        Rails.error.report(error, context: { user_id: user.id, builder_session_id: builder_session.id })
      end
      next if reminders.empty?

      connection = builder_session.program.calendar_connection
      next unless connection&.status == "connected"

      declined_emails = client_for(connection).declined_attendee_emails(
        calendar_id: connection.google_calendar_id,
        event_id: builder_session.google_event_id
      )
      reminders.each do |reminder|
        reminder.process!(declined: declined_emails.include?(reminder.user.email))
      rescue StandardError => error
        # The next minute retries unprocessed reminders without blocking other recipients.
        Rails.error.report(error, context: { user_id: reminder.user_id, builder_session_id: builder_session.id })
      end
    rescue StandardError => error
      Rails.error.report(error, context: { builder_session_id: builder_session.id })
    end
  end

  private

  def client_for(connection)
    GoogleWorkspace::CalendarClient.new(connection:)
  end
end
