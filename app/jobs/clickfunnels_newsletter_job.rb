class ClickfunnelsNewsletterJob < ApplicationJob
  queue_as :default
  retry_on ClickfunnelsNewsletter::TransientError, wait: :polynomially_longer, attempts: 8

  def perform(user_id)
    user = User.find(user_id)
    return unless user.verified? && user.newsletter_confirmed_at?

    configuration = ClickfunnelsNewsletter.configuration
    unless configuration.enabled
      user.update!(clickfunnels_sync_status: "skipped_local")
      return
    end

    unless configuration.configured?
      user.update!(clickfunnels_sync_status: "missing_configuration")
      return
    end

    user.with_lock do
      return if user.clickfunnels_sync_status == "subscribed"

      result = ClickfunnelsNewsletter.new(user, configuration: configuration).subscribe!
      user.update!(
        clickfunnels_contact_id: result.fetch(:contact_id),
        clickfunnels_contact_public_id: result.fetch(:contact_public_id),
        clickfunnels_sync_status: result.fetch(:status)
      )
    end
  rescue StandardError
    user&.update!(clickfunnels_sync_status: "failed")
    raise
  end
end
