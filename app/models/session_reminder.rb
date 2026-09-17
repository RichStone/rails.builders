class SessionReminder < ApplicationRecord
  belongs_to :user
  belongs_to :builder_session

  def processed? = sent_at? || calendar_declined_at?

  def process!(declined:)
    with_lock do
      next if processed?
      next unless builder_session.reload.scheduled_starts_at == scheduled_starts_at

      if declined
        update!(calendar_declined_at: Time.current)
        next
      end

      # ponytail: serialize delivery for this small group; use provider idempotency
      # if volume requires moving delivery outside the database transaction.
      message = UserMailer.session_reminder(user, builder_session).deliver_now
      update!(sent_at: Time.current) if message
    end
  end
end
