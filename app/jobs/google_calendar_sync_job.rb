class GoogleCalendarSyncJob < ApplicationJob
  queue_as :default

  def perform(connection_id = nil)
    connections = ProgramCalendarConnection.where(status: %w[connected error])
    connections = connections.where(id: connection_id) if connection_id

    connections.find_each do |connection|
      GoogleCalendarSync.new(connection: connection, client: client_for(connection)).call
    rescue StandardError => error
      Rails.logger.error("Google Calendar sync failed connection_id=#{connection.id} error=#{error.class.name}")
    end
  end

  private

  def client_for(connection)
    GoogleWorkspace::CalendarClient.new(connection: connection)
  end
end
