class WeeklyCherryDeliveryJob < ApplicationJob
  def perform
    WeeklyCherryDelivery.pending.find_each do |delivery|
      delivery.process!
    rescue ActiveRecord::RecordNotFound
      next
    rescue StandardError => error
      Rails.error.report(StandardError.new("Weekly Builders Cherry could not send: #{error.class}"), context: { delivery_id: delivery.id })
    end
    WeeklyCherryDelivery.where(summary: false).where.not(sent_at: nil).where.not(copy: nil)
      .where.not(builder_session_transcript_id: WeeklyCherryDelivery.where(summary: true).select(:builder_session_transcript_id))
      .update_all(copy: nil)
  end
end
