class SessionReminderJob < ApplicationJob
  def perform
    BuilderSession.where(state: "ready", scheduled_starts_at: Time.current..168.hours.from_now).find_each do |builder_session|
      User.active.or(User.where(facilitator: true)).find_each do |user|
        next unless user.session_reminder_due?(builder_session)

        reminder = SessionReminder.create_or_find_by!(user: user, builder_session: builder_session, scheduled_starts_at: builder_session.scheduled_starts_at)
        reminder.deliver!
      rescue StandardError => error
        # The next minute retries unsent reminders without blocking other recipients.
        Rails.error.report(error, context: { user_id: user.id, builder_session_id: builder_session.id })
      end
    end
  end
end
