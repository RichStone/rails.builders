class BuilderSessionMaintenanceJob < ApplicationJob
  queue_as :default

  def perform
    synchronized_at = Time.current

    BuilderSession.active.find_each do |builder_session|
      builder_session.synchronize!(at: synchronized_at)
    rescue StandardError => error
      Rails.logger.error("Builder Session maintenance failed builder_session_id=#{builder_session.id} error=#{error.class.name}")
    end
  end
end
