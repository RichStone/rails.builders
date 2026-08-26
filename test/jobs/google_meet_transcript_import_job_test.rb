require "test_helper"

class GoogleMeetTranscriptImportJobTest < ActiveJob::TestCase
  FakeClient = Struct.new(:result, :error, :calls) do
    def transcript_for(builder_session)
      self.calls += 1
      raise error if error

      result
    end
  end

  class StubbedJob < GoogleMeetTranscriptImportJob
    attr_accessor :client

    private

    def client_for(connection)
      client
    end
  end

  setup do
    @facilitator = User.create!(
      email: "facilitator@example.com",
      name: "Facilitator",
      facilitator: true,
      enrollment_status: "active",
      verified_at: Time.current
    )
    @program = Program.create!(
      name: "Continuous",
      starts_on: Date.new(2026, 8, 20),
      ends_on: Date.new(2026, 12, 17),
      capacity: 9,
      main_facilitator: @facilitator
    )
    @program.create_calendar_connection!(
      facilitator: @facilitator,
      google_account_email: "facilitator@looplabs.cc",
      google_calendar_id: "continuous@group.calendar.google.com",
      google_calendar_name: "Rails Builders — Continuous",
      oauth_token_json: '{"refresh_token":"secret"}',
      status: "connected"
    )
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
    travel_to(Time.zone.parse("2026-08-24 19:00")) { @builder_session.finish! }
    travel_to Time.zone.parse("2026-08-24 19:05")
    @transcript = @builder_session.reload.transcript
  end

  test "imports a due transcript through the Meet client" do
    client = FakeClient.new({
      status: :ready,
      conference_record_name: "conferenceRecords/record-1",
      transcript_names: [ "conferenceRecords/record-1/transcripts/transcript-1" ],
      segments: [
        { speaker: "Ada", started_at: Time.zone.parse("2026-08-24 18:03"), text: "I shipped it." }
      ]
    }, nil, 0)
    job = StubbedJob.new
    job.client = client

    job.perform(@transcript.id)

    assert_equal "ready", @transcript.reload.state
    assert_equal "google", @transcript.source
    assert_includes @transcript.content, "Ada"
    assert_equal 1, client.calls
  end

  test "retries processing transcripts and makes one final import attempt at the twenty-four hour deadline" do
    client = FakeClient.new({ status: :processing }, nil, 0)
    job = StubbedJob.new
    job.client = client
    ended_at = @builder_session.ended_at

    travel_to ended_at + 23.hours + 59.minutes do
      job.perform(@transcript.id)

      assert_equal "processing", @transcript.reload.state
      assert_equal 1, @transcript.attempts
      assert_equal ended_at + 24.hours, @transcript.next_attempt_at
    end

    client.result = {
      status: :ready,
      conference_record_name: "conferenceRecords/final-record",
      transcript_names: [],
      segments: [
        { speaker: "Ada", started_at: ended_at, text: "Generated just before the deadline." }
      ]
    }
    travel_to ended_at + 24.hours do
      job.perform

      assert_equal "ready", @transcript.reload.state
      assert_nil @transcript.next_attempt_at
      assert_equal 2, client.calls
    end
  end

  test "expires a transcript after the import window when no final attempt was scheduled" do
    client = FakeClient.new({ status: :processing }, nil, 0)
    job = StubbedJob.new
    job.client = client

    travel_to @builder_session.ended_at + 24.hours + 1.minute do
      job.perform(@transcript.id)
    end

    assert_equal "unavailable", @transcript.reload.state
    assert_equal 0, client.calls
  end

  test "records a retry without leaking an adapter error message" do
    client = FakeClient.new(nil, RuntimeError.new("secret response body"), 0)
    job = StubbedJob.new
    job.client = client

    travel_to @builder_session.ended_at + 5.minutes do
      job.perform(@transcript.id)
    end

    assert_equal "processing", @transcript.reload.state
    assert_equal 1, @transcript.attempts
    assert_equal "RuntimeError", @transcript.last_error_code
    assert_equal @transcript.last_attempted_at + 5.minutes, @transcript.next_attempt_at
    assert_not_includes @transcript.last_error_code, "secret"
  end

  test "requests a Google reconnect when transcript authorization expires" do
    job = StubbedJob.new
    job.client = FakeClient.new(nil, GoogleWorkspace::AuthorizationRequired.new("secret response body"), 0)

    job.perform(@transcript.id)

    assert_equal "reauthorization_required", @program.calendar_connection.reload.status
    assert_equal "processing", @transcript.reload.state
    assert_equal "GoogleWorkspace::AuthorizationRequired", @transcript.last_error_code
  end

  test "does not resurrect a transcript deleted while Google responds" do
    transcript = @transcript
    client = Object.new
    client.define_singleton_method(:transcript_for) do |_builder_session|
      transcript.delete_content!
      raise RuntimeError, "late Google failure"
    end
    job = StubbedJob.new
    job.client = client

    job.perform(@transcript.id)

    assert_equal "deleted", @transcript.reload.state
    assert_nil @transcript.content
  end

  test "a stale authorization failure cannot invalidate newly connected Google credentials" do
    transcript = @transcript
    connection = @program.calendar_connection
    client = Object.new
    client.define_singleton_method(:transcript_for) do |_builder_session|
      transcript.replace_with_manual!("Facilitator fallback")
      connection.update!(oauth_token_json: '{"refresh_token":"new-credentials"}', status: "connected")
      raise GoogleWorkspace::AuthorizationRequired, "old credentials expired"
    end
    job = StubbedJob.new
    job.client = client

    job.perform(@transcript.id)

    assert_equal "connected", connection.reload.status
    assert_includes connection.oauth_token_json, "new-credentials"
    assert_equal "manual", transcript.reload.source
  end
end
