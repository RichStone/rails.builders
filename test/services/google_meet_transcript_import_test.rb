require "test_helper"

class GoogleMeetTranscriptImportTest < ActiveSupport::TestCase
  FakeClient = Struct.new(:result) do
    def transcript_for(builder_session)
      result
    end
  end

  setup do
    @facilitator = User.create!(email: "facilitator@example.com", name: "Facilitator", facilitator: true, enrollment_status: "active", verified_at: Time.current)
    @program = Program.create!(name: "Continuous", starts_on: Date.new(2026, 8, 20), ends_on: Date.new(2026, 12, 17), capacity: 9, main_facilitator: @facilitator)
    @builder_session = @program.builder_sessions.create!(
      assigned_facilitator: @facilitator,
      google_event_id: "calendar-event-1",
      title: "Product teardown",
      meet_url: "https://meet.google.com/abc-defg-hij",
      scheduled_starts_at: Time.zone.parse("2026-08-24 18:00"),
      scheduled_ends_at: Time.zone.parse("2026-08-24 19:00"),
      time_zone: "Europe/Madrid"
    )
    travel_to(Time.zone.parse("2026-08-24 18:00")) { @builder_session.start!(facilitator: @facilitator) }
    assert_equal "connection", @builder_session.reload.state
    travel_to(Time.zone.parse("2026-08-24 19:00")) { @builder_session.finish! }
    assert_equal "completed", @builder_session.reload.state
    @transcript = BuilderSessionTranscript.find_by!(builder_session: @builder_session)
  end

  test "imports speaker-labelled structured entries as a read-only transcript" do
    client = FakeClient.new({
      status: :ready,
      conference_record_name: "conferenceRecords/record-1",
      transcript_names: [ "conferenceRecords/record-1/transcripts/transcript-1" ],
      segments: [
        { speaker: "Ada", started_at: Time.zone.parse("2026-08-24 18:03:05"), text: "I shipped the onboarding flow." },
        { speaker: "Grace", started_at: Time.zone.parse("2026-08-24 18:03:20"), text: "The failure mode is clearer now." }
      ]
    })

    GoogleMeetTranscriptImport.new(transcript: @transcript, client: client).call

    assert_equal "ready", @transcript.reload.state
    assert_equal "google", @transcript.source
    assert_includes @transcript.content, "20:03 · Ada\nI shipped the onboarding flow."
    assert_includes @transcript.content, "20:03 · Grace\nThe failure mode is clearer now."
    assert_equal "conferenceRecords/record-1", @transcript.google_conference_record_name
    assert_not_includes @transcript.read_attribute_before_type_cast(:content), "onboarding flow"
    assert_not_includes @transcript.read_attribute_before_type_cast(:google_conference_record_name), "record-1"
    assert_not_includes @transcript.read_attribute_before_type_cast(:google_transcript_names), "transcript-1"
  end

  test "keeps a processing transcript retryable" do
    client = FakeClient.new({ status: :processing })

    GoogleMeetTranscriptImport.new(transcript: @transcript, client: client).call

    assert_equal "processing", @transcript.reload.state
    assert_equal 1, @transcript.attempts
    assert @transcript.next_attempt_at > Time.current
  end

  test "does not overwrite a manual transcript added while Google responds" do
    transcript = @transcript
    client = Object.new
    client.define_singleton_method(:transcript_for) do |_builder_session|
      transcript.replace_with_manual!("Facilitator notes")
      {
        status: :ready,
        conference_record_name: "conferenceRecords/record-1",
        transcript_names: [],
        segments: [
          { speaker: "Ada", started_at: Time.zone.parse("2026-08-24 18:03"), text: "Google copy" }
        ]
      }
    end

    GoogleMeetTranscriptImport.new(transcript: @transcript, client: client).call

    assert_equal "manual", @transcript.reload.source
    assert_equal "Facilitator notes", @transcript.content
  end
end
