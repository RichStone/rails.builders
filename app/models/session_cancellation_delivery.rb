class SessionCancellationDelivery < ApplicationRecord
  RetryWindowExpired = Class.new(StandardError)

  belongs_to :builder_session
  belongs_to :user

  def processed? = sent_at? || skipped_at?
  def retry_expired? = first_attempted_at? && first_attempted_at <= 23.hours.ago

  def process!
    # Commit this before sending so an uncertain provider result cannot reset
    # the retry window. Resend retains idempotency keys for only 24 hours.
    with_lock do
      return if processed?

      update!(first_attempted_at: Time.current) unless first_attempted_at?
    end

    with_lock do
      next if processed?
      if retry_expired?
        raise RetryWindowExpired, "Verify this cancellation email with the provider before retrying; its safe retry window has expired."
      end

      # ponytail: hold the lock for this small group; move provider calls outside
      # the transaction if volume grows, retaining claims and provider idempotency.
      message = UserMailer.session_cancellation(user, builder_session).deliver_now
      update!(message ? { sent_at: Time.current } : { skipped_at: Time.current })
    end
  end
end
