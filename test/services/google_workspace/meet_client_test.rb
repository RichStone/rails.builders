require "test_helper"

class GoogleWorkspace::MeetClientTest < ActiveSupport::TestCase
  Meet = Google::Apis::MeetV2
  SessionSnapshot = Data.define(:meet_url, :started_at, :ended_at, :scheduled_starts_at, :scheduled_ends_at)

  class FakeService
    attr_reader :space_names, :conference_filters, :transcript_parents

    def initialize(transcript_state: "FILE_GENERATED", records: nil)
      @transcript_state = transcript_state
      @records = records || [ conference_record("record-1", "2026-08-24T16:00:00Z", "2026-08-24T17:00:00Z") ]
      @space_names = []
      @conference_filters = []
      @transcript_parents = []
    end

    def get_space(name, fields:)
      @space_names << name
      raise unless fields == "name"

      Meet::Space.new(name: "spaces/stable-space")
    end

    def list_conference_records(filter:, fields:, page_size:, page_token: nil)
      @conference_filters << filter
      raise unless fields == GoogleWorkspace::MeetClient::CONFERENCE_FIELDS

      Meet::ListConferenceRecordsResponse.new(conference_records: @records)
    end

    def list_conference_record_transcripts(parent, fields:, page_size:, page_token: nil)
      @transcript_parents << parent
      raise unless fields == GoogleWorkspace::MeetClient::TRANSCRIPT_FIELDS

      Meet::ListTranscriptsResponse.new(transcripts: [
        Meet::Transcript.new(
          name: "conferenceRecords/record-1/transcripts/transcript-1",
          state: @transcript_state
        )
      ])
    end

    def list_conference_record_participants(parent, fields:, page_size:, page_token: nil)
      raise unless fields == GoogleWorkspace::MeetClient::PARTICIPANT_FIELDS

      Meet::ListParticipantsResponse.new(participants: [
        Meet::Participant.new(
          name: "conferenceRecords/record-1/participants/participant-1",
          signedin_user: Meet::SignedinUser.new(display_name: "Ada")
        )
      ])
    end

    def list_conference_record_transcript_entries(parent, fields:, page_size:, page_token: nil)
      raise unless fields == GoogleWorkspace::MeetClient::TRANSCRIPT_ENTRY_FIELDS

      case page_token
      when nil
        Meet::ListTranscriptEntriesResponse.new(
          transcript_entries: [
            Meet::TranscriptEntry.new(
              participant: "conferenceRecords/record-1/participants/participant-1",
              start_time: "2026-08-24T15:59:59Z",
              text: "Private conversation before the app session."
            ),
            Meet::TranscriptEntry.new(
              participant: "conferenceRecords/record-1/participants/participant-1",
              start_time: "2026-08-24T16:03:05Z",
              text: "I shipped the onboarding flow."
            )
          ],
          next_page_token: "next-page"
        )
      when "next-page"
        Meet::ListTranscriptEntriesResponse.new(transcript_entries: [
          Meet::TranscriptEntry.new(
            participant: "conferenceRecords/record-1/participants/missing",
            start_time: "2026-08-24T16:04:00Z",
            text: "A second segment."
          ),
          Meet::TranscriptEntry.new(
            participant: "conferenceRecords/record-1/participants/participant-1",
            start_time: "2026-08-24T17:00:01Z",
            text: "Private conversation after the app session."
          )
        ])
      else
        raise "unexpected page token"
      end
    end


    private

    def conference_record(id, starts_at, ends_at)
      Meet::ConferenceRecord.new(
        name: "conferenceRecords/#{id}",
        space: "spaces/stable-space",
        start_time: starts_at,
        end_time: ends_at
      )
    end
  end

  test "resolves the stable Meet space and retrieves generated transcript entries across pages" do
    service = FakeService.new
    session = session_snapshot(meet_url: "https://meet.google.com/abc-defg-hij")
    client = GoogleWorkspace::MeetClient.new(connection: Object.new, service: service)

    result = client.transcript_for(session)

    assert_equal :ready, result[:status]
    assert_equal "conferenceRecords/record-1", result[:conference_record_name]
    assert_equal [ "conferenceRecords/record-1/transcripts/transcript-1" ], result[:transcript_names]
    assert_equal [
      { speaker: "Ada", started_at: Time.iso8601("2026-08-24T16:03:05Z"), text: "I shipped the onboarding flow." },
      { speaker: "Unknown speaker", started_at: Time.iso8601("2026-08-24T16:04:00Z"), text: "A second segment." }
    ], result[:segments]
    assert_equal [ "spaces/abc-defg-hij" ], service.space_names
    assert_includes service.conference_filters.first, 'space.name = "spaces/stable-space"'
    assert_equal [ "conferenceRecords/record-1" ], service.transcript_parents
  end

  test "returns processing until Google finishes generating every transcript" do
    result = GoogleWorkspace::MeetClient.new(
      connection: Object.new,
      service: FakeService.new(transcript_state: "ENDED")
    ).transcript_for(session_snapshot(meet_url: "https://meet.google.com/abc-defg-hij"))

    assert_equal :processing, result[:status]
    assert_equal "conferenceRecords/record-1", result[:conference_record_name]
  end

  test "selects only the conference that overlaps the app session" do
    records = [
      Meet::ConferenceRecord.new(
        name: "conferenceRecords/previous",
        space: "spaces/stable-space",
        start_time: "2026-08-24T15:59:00Z",
        end_time: "2026-08-24T16:00:00Z"
      ),
      Meet::ConferenceRecord.new(
        name: "conferenceRecords/current",
        space: "spaces/stable-space",
        start_time: "2026-08-24T16:01:00Z",
        end_time: "2026-08-24T16:59:00Z"
      )
    ]
    service = FakeService.new(records: records)

    GoogleWorkspace::MeetClient.new(connection: Object.new, service: service)
      .transcript_for(session_snapshot(meet_url: "https://meet.google.com/abc-defg-hij"))

    assert_equal [ "conferenceRecords/current" ], service.transcript_parents
  end

  test "fails closed when more than one conference overlaps the app session" do
    records = %w[first second].map do |id|
      Meet::ConferenceRecord.new(
        name: "conferenceRecords/#{id}",
        space: "spaces/stable-space",
        start_time: "2026-08-24T16:05:00Z",
        end_time: "2026-08-24T16:55:00Z"
      )
    end
    service = FakeService.new(records: records)

    result = GoogleWorkspace::MeetClient.new(connection: Object.new, service: service)
      .transcript_for(session_snapshot(meet_url: "https://meet.google.com/abc-defg-hij"))

    assert_equal({ status: :processing }, result)
    assert_empty service.transcript_parents
  end

  test "rejects non-Google meeting links without making an API call" do
    service = FakeService.new

    result = GoogleWorkspace::MeetClient.new(connection: Object.new, service: service).transcript_for(
      session_snapshot(meet_url: "https://example.com/abc-defg-hij")
    )

    assert_equal({ status: :unavailable }, result)
    assert_empty service.space_names
  end

  private

  def session_snapshot(meet_url:)
    SessionSnapshot.new(
      meet_url: meet_url,
      started_at: Time.iso8601("2026-08-24T16:00:00Z"),
      ended_at: Time.iso8601("2026-08-24T17:00:00Z"),
      scheduled_starts_at: Time.iso8601("2026-08-24T16:00:00Z"),
      scheduled_ends_at: Time.iso8601("2026-08-24T17:00:00Z")
    )
  end
end
