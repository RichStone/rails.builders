require "google/apis/calendar_v3"
require "time"

module GoogleWorkspace
  class CalendarClient
    PAGE_SIZE = 2_500
    CALENDAR_LIST_FIELDS = "items(id,summary,summaryOverride,timeZone,dataOwner,primary,deleted),nextPageToken"
    EVENT_FIELDS = [
      "items(id,status,summary,description,location,hangoutLink",
      "conferenceData(conferenceSolution(key(type)),entryPoints(entryPointType,uri))",
      "start(date,dateTime,timeZone),end(date,dateTime,timeZone))",
      "nextPageToken,timeZone"
    ].join(",")

    def initialize(connection:, credentials: nil, service: nil)
      @connection = connection
      @service = service || build_service(credentials)
    end

    def account_email
      @account_email ||= service.get_calendar_list("primary", fields: "id").id.to_s.strip.downcase
    end

    def owned_secondary_calendars
      paginate_calendar_list.filter_map do |calendar|
        next if calendar.primary || calendar.deleted

        data_owner = calendar.data_owner.to_s.strip.downcase
        next unless data_owner == account_email

        {
          id: calendar.id,
          name: calendar.summary_override.presence || calendar.summary,
          time_zone: calendar.time_zone,
          data_owner: data_owner
        }
      end
    end

    def list_events(calendar_id:, starts_at:, ends_at:)
      events = []
      page_token = nil

      loop do
        page = service.list_events(
          calendar_id,
          event_types: [ "default" ],
          fields: EVENT_FIELDS,
          max_results: PAGE_SIZE,
          page_token: page_token,
          show_deleted: true,
          single_events: true,
          time_min: starts_at.iso8601,
          time_max: ends_at.iso8601
        )
        events.concat(Array(page.items).map { |event| normalize_event(event, page.time_zone) })
        page_token = page.next_page_token
        break if page_token.blank?
      end

      events
    end

    private

    attr_reader :connection, :service

    def build_service(credentials)
      authorization = credentials || Authorization.new(connection: connection).credentials
      raise AuthorizationRequired, "Google authorization is required" unless authorization

      Google::Apis::CalendarV3::CalendarService.new.tap do |client|
        client.authorization = authorization
        configure(client)
      end
    end

    def configure(client)
      client.client_options.application_name = "Rails Builders"
      client.client_options.open_timeout_sec = 5
      client.client_options.read_timeout_sec = 20
      client.client_options.send_timeout_sec = 20
      client.client_options.log_http_requests = false
      client.request_options.retries = 3
      client.request_options.max_elapsed_time = 30
    end

    def paginate_calendar_list
      calendars = []
      page_token = nil

      loop do
        page = service.list_calendar_lists(
          fields: CALENDAR_LIST_FIELDS,
          max_results: 250,
          min_access_role: "owner",
          page_token: page_token,
          show_deleted: false,
          show_hidden: true
        )
        calendars.concat(Array(page.items))
        page_token = page.next_page_token
        break if page_token.blank?
      end

      calendars
    end

    def normalize_event(event, calendar_time_zone)
      normalized = { id: event.id, status: event.status }
      return normalized if event.status == "cancelled"
      return normalized.merge(all_day: true) if event.start&.date

      normalized.merge(
        title: event.summary,
        description: event.description,
        location: event.location,
        meet_url: meet_url(event),
        starts_at: parse_time(event.start&.date_time),
        ends_at: parse_time(event.end&.date_time),
        time_zone: event.start&.time_zone.presence || calendar_time_zone,
        all_day: false
      )
    end

    def meet_url(event)
      candidates = [ event.hangout_link ]
      if event.conference_data&.conference_solution&.key&.type == "hangoutsMeet"
        candidates.concat(Array(event.conference_data.entry_points).filter_map do |entry|
          entry.uri if entry.entry_point_type == "video"
        end)
      end

      candidates.filter_map { |candidate| MeetLink.url(candidate) }.first
    end

    def parse_time(value)
      return value.to_time if value.respond_to?(:to_time)

      Time.iso8601(value.to_s)
    end
  end
end
