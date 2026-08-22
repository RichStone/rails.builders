require "google/apis/meet_v2"
require "time"

module GoogleWorkspace
  class MeetClient
    CONFERENCE_FIELDS = "conferenceRecords(name,startTime,endTime),nextPageToken"
    PARTICIPANT_FIELDS = [
      "participants(name,signedinUser(displayName),anonymousUser(displayName),phoneUser(displayName))",
      "nextPageToken"
    ].join(",")
    TRANSCRIPT_FIELDS = "transcripts(name,state),nextPageToken"
    TRANSCRIPT_ENTRY_FIELDS = "transcriptEntries(participant,startTime,text),nextPageToken"

    def initialize(connection:, credentials: nil, service: nil)
      @connection = connection
      @service = service || build_service(credentials)
    end

    def transcript_for(builder_session)
      meeting_code = MeetLink.code(builder_session.meet_url)
      return { status: :unavailable } unless meeting_code

      session_start = builder_session.started_at || builder_session.scheduled_starts_at
      session_end = builder_session.ended_at || builder_session.scheduled_ends_at || session_start + 5.hours
      space = service.get_space("spaces/#{meeting_code}", fields: "name")
      conference_record = find_conference_record(space.name, session_start:, session_end:)
      return { status: :processing } unless conference_record

      transcripts = list_transcripts(conference_record.name)
      return processing(conference_record) if transcripts.empty?
      return processing(conference_record) unless transcripts.all? { |transcript| transcript.state == "FILE_GENERATED" }

      participants = participant_names(conference_record.name)
      segments = transcripts.flat_map do |transcript|
        list_transcript_entries(transcript.name).filter_map do |entry|
          started_at = parse_time(entry.start_time)
          next unless started_at.between?(session_start, session_end)

          {
            speaker: participants.fetch(entry.participant, "Unknown speaker"),
            started_at: started_at,
            text: entry.text.to_s
          }
        end
      end.sort_by { |segment| segment.fetch(:started_at) }

      {
        status: :ready,
        conference_record_name: conference_record.name,
        transcript_names: transcripts.map(&:name),
        segments: segments
      }
    end

    private

    attr_reader :connection, :service

    def build_service(credentials)
      authorization = credentials || Authorization.new(connection: connection).credentials
      raise AuthorizationRequired, "Google authorization is required" unless authorization

      Google::Apis::MeetV2::MeetService.new.tap do |client|
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

    def find_conference_record(space_name, session_start:, session_end:)
      window_start = session_start - 2.hours
      window_end = session_end + 2.hours
      filter = [
        %(space.name = "#{escape_filter(space_name)}"),
        %(start_time >= "#{window_start.utc.iso8601}"),
        %(start_time <= "#{window_end.utc.iso8601}")
      ].join(" AND ")
      records = paginate(:conference_records) do |page_token|
        service.list_conference_records(
          fields: CONFERENCE_FIELDS,
          filter: filter,
          page_size: 100,
          page_token: page_token
        )
      end

      overlapping = records.select do |record|
        record_start = parse_time(record.start_time)
        record_end = parse_time(record.end_time) if record.end_time
        record_start < session_end && (record_end.nil? || record_end > session_start)
      end
      overlapping.one? ? overlapping.first : nil
    end

    def list_transcripts(conference_record_name)
      paginate(:transcripts) do |page_token|
        service.list_conference_record_transcripts(
          conference_record_name,
          fields: TRANSCRIPT_FIELDS,
          page_size: 100,
          page_token: page_token
        )
      end
    end

    def participant_names(conference_record_name)
      paginate(:participants) do |page_token|
        service.list_conference_record_participants(
          conference_record_name,
          fields: PARTICIPANT_FIELDS,
          page_size: 250,
          page_token: page_token
        )
      end.to_h { |participant| [ participant.name, participant_name(participant) ] }
    end

    def participant_name(participant)
      participant.signedin_user&.display_name.presence ||
        participant.anonymous_user&.display_name.presence ||
        participant.phone_user&.display_name.presence ||
        "Unknown speaker"
    end

    def list_transcript_entries(transcript_name)
      paginate(:transcript_entries) do |page_token|
        service.list_conference_record_transcript_entries(
          transcript_name,
          fields: TRANSCRIPT_ENTRY_FIELDS,
          page_size: 100,
          page_token: page_token
        )
      end
    end

    def paginate(collection)
      resources = []
      page_token = nil

      loop do
        page = yield(page_token)
        resources.concat(Array(page.public_send(collection)))
        page_token = page.next_page_token
        break if page_token.blank?
      end

      resources
    end

    def processing(conference_record)
      { status: :processing, conference_record_name: conference_record.name }
    end

    def escape_filter(value)
      value.to_s.gsub("\\", "\\\\").gsub('"', '\\"')
    end

    def parse_time(value)
      return value.to_time if value.respond_to?(:to_time)

      Time.iso8601(value.to_s)
    end
  end
end
