class SessionReminder < ApplicationRecord
  belongs_to :user
  belongs_to :builder_session

  def deliver!
    with_lock do
      next if sent_at?
      next unless builder_session.reload.scheduled_starts_at == scheduled_starts_at

      # ponytail: serialize delivery for this small group; use provider idempotency
      # if volume requires moving delivery outside the database transaction.
      message = UserMailer.session_reminder(user, builder_session).deliver_now
      update!(sent_at: Time.current) if message
    end
  end
end
