require "test_helper"

class GoogleCalendarNotesSyncJobTest < ActiveJob::TestCase
  FakeClient = Struct.new(:notes, :error, :calls) do
    def notes_for(session)
      self.calls += 1
      raise error if error

      notes
    end
  end

  class StubbedJob < GoogleCalendarNotesSyncJob
    attr_accessor :client

    private

    def client_for(connection) = client
  end

  setup do
    @facilitator = User.create!(email: "facilitator@example.com", facilitator: true, verified_at: Time.current)
    @program = Program.create!(name: "Builders", starts_on: Date.new(2026, 9, 1), ends_on: Date.new(2026, 12, 17), main_facilitator: @facilitator)
    @connection = @program.create_calendar_connection!(facilitator: @facilitator,
      google_account_email: @facilitator.email, google_calendar_id: "sessions-calendar",
      google_calendar_name: "Sessions", oauth_token_json: "{}", status: "connected")
    @session = @program.builder_sessions.create!(google_event_id: "weekly-occurrence", title: "Weekly session",
      source_calendar_id: "sessions-calendar", time_zone: "Europe/Madrid",
      scheduled_starts_at: Time.utc(2026, 10, 29, 16, 30), scheduled_ends_at: Time.utc(2026, 10, 29, 18))
    travel_to(Time.utc(2026, 10, 29, 16, 33)) { @session.start!(facilitator: @facilitator) }
    travel_to(Time.utc(2026, 10, 29, 18, 5)) { @session.finish! }
    @transcript = @session.reload.transcript
    @client = FakeClient.new("# Full notes\n\nA concrete builder update.", nil, 0)
    @job = StubbedJob.new
    @job.client = @client
  end

  test "finishing schedules notes one hour after actual end and the sweep imports independently of the transcript" do
    assert_equal @session.ended_at + 1.hour, @transcript.calendar_notes_next_attempt_at

    travel_to @session.ended_at + 59.minutes do
      @job.perform
      assert_equal 0, @client.calls
    end
    travel_to @session.ended_at + 1.hour do
      @job.perform
      assert_equal @client.notes, @transcript.reload.calendar_notes
      assert_equal Time.current, @transcript.calendar_notes_synced_at
      assert_equal "pending", @transcript.state
      assert_nil @transcript.content
      assert_nil @transcript.wispr_meeting_id
      @job.perform
      assert_equal 1, @client.calls
    end
  end

  test "manual sync can run immediately and preserves manual summaries chat and transcript" do
    @transcript.replace_with_manual!("Spoken transcript", summary_notes: "Edited summary", session_analysis: "Our analysis")
    @session.create_chat_log!(content: "Saved chat", source: "manual", imported_at: Time.current)
    travel_to @session.ended_at + 5.minutes do
      assert_enqueued_with(job: GoogleCalendarNotesSyncJob, args: [ @session.id ]) do
        assert @session.request_calendar_notes_sync!
      end
      @job.perform(@session.id)
    end

    assert_equal @client.notes, @transcript.reload.calendar_notes
    assert_equal "Spoken transcript", @transcript.content
    assert_equal "Edited summary", @transcript.summary_notes
    assert_equal "Our analysis", @transcript.session_analysis
    assert_equal "Saved chat", @session.reload.chat_log.content
    assert_equal @session.ended_at + 1.hour, @transcript.calendar_notes_next_attempt_at
    assert_not_includes @transcript.ciphertext_for(:calendar_notes), "concrete builder update"
    @client.notes = "Updated notes after the hour"
    travel_to @session.ended_at + 1.hour do
      @job.perform
    end
    assert_equal "Updated notes after the hour", @transcript.reload.calendar_notes
    assert_nil @transcript.calendar_notes_next_attempt_at
  end

  test "missing notes retry until the twenty-four hour deadline without erasing a previous copy" do
    @transcript.update!(calendar_notes: "Retained notes")
    @client.notes = nil
    travel_to @session.ended_at + 1.hour do
      @job.perform
      assert_equal "NotesNotFound", @transcript.reload.calendar_notes_error_code
      assert_equal Time.current + 15.minutes, @transcript.calendar_notes_next_attempt_at
      assert_equal "Retained notes", @transcript.calendar_notes
    end
    travel_to @session.ended_at + 24.hours do
      @job.perform
      assert_nil @transcript.reload.calendar_notes_next_attempt_at
    end
  end

  test "manual transcript added after calendar notes preserves them" do
    @transcript.update!(calendar_notes: "Calendar notes")
    @transcript.replace_with_manual!("Later transcript")
    assert_equal "Calendar notes", @transcript.reload.calendar_notes
  end

  test "a deleted record cannot be queued or restored by an in-flight response" do
    record = @transcript
    @client.define_singleton_method(:notes_for) do |_session|
      record.delete_content!
      "Too late"
    end
    travel_to @session.ended_at + 1.hour do
      @job.perform
    end
    assert_equal "deleted", @transcript.reload.state
    assert_nil @transcript.calendar_notes
    assert_nil @transcript.calendar_notes_next_attempt_at
    assert_not @session.request_calendar_notes_sync!
  end

  test "duplicate workers cannot claim the same notes request" do
    calls = 0
    job = @job
    @client.define_singleton_method(:notes_for) do |_session|
      calls += 1
      job.perform
      "Only one request"
    end
    travel_to @session.ended_at + 1.hour do
      @job.perform
    end
    assert_equal 1, calls
    assert_equal "Only one request", @transcript.reload.calendar_notes
  end

  test "a later manual request supersedes an older in-flight response" do
    session = @session
    @client.define_singleton_method(:notes_for) do |_session|
      session.request_calendar_notes_sync!
      "Stale response"
    end
    travel_to @session.ended_at + 1.hour do
      @job.perform
    end
    assert_nil @transcript.reload.calendar_notes
    assert_not_nil @transcript.calendar_notes_next_attempt_at
  end

  test "calendar identity mismatch does not fetch or replace notes" do
    @connection.update!(google_calendar_id: "different-calendar")
    travel_to @session.ended_at + 1.hour do
      @job.perform
    end
    assert_equal 0, @client.calls
    assert_equal "CalendarMismatch", @transcript.reload.calendar_notes_error_code
    assert_nil @transcript.calendar_notes_next_attempt_at
  end

  test "corrected end times move the unattempted automatic sync" do
    @session.correct_times!(started_at: @session.started_at, ended_at: @session.ended_at + 10.minutes)
    assert_equal @session.ended_at + 1.hour, @transcript.reload.calendar_notes_next_attempt_at
  end

  test "notes permission failure does not disable existing Calendar or Meet credentials" do
    @client.error = GoogleWorkspace::NotesClient::AuthorizationRequired.new("private response")
    travel_to @session.ended_at + 1.hour do
      @job.perform
    end
    assert_equal "GoogleNotesPermissionRequired", @transcript.reload.calendar_notes_error_code
    assert_nil @transcript.calendar_notes_next_attempt_at
    assert_equal "connected", @connection.reload.status
  end

  test "provider errors retain notes and record only a safe code" do
    @transcript.update!(calendar_notes: "Existing notes")
    @client.error = RuntimeError.new("private response body")
    travel_to @session.ended_at + 1.hour do
      @job.perform
      assert_equal "RuntimeError", @transcript.reload.calendar_notes_error_code
      assert_equal "Existing notes", @transcript.calendar_notes
      assert_equal Time.current + 15.minutes, @transcript.calendar_notes_next_attempt_at
    end
  end

  test "deleting a completed record erases notes and cancels pending sync" do
    @transcript.update!(calendar_notes: "Delete this private material", calendar_notes_synced_at: Time.current)
    @transcript.delete_content!
    assert_nil @transcript.reload.calendar_notes
    assert_nil @transcript.calendar_notes_synced_at
    assert_nil @transcript.calendar_notes_next_attempt_at
  end

  test "disconnecting while notes are downloaded does not save the late response" do
    connection = @connection
    @client.define_singleton_method(:notes_for) do |_session|
      connection.destroy!
      "Downloaded before disconnect"
    end
    travel_to @session.ended_at + 1.hour do
      @job.perform
    end
    assert_nil @transcript.reload.calendar_notes
    assert_equal "CalendarConnectionMissing", @transcript.calendar_notes_error_code
  end

  test "an early manual failure cannot postpone the one-hour automatic attempt" do
    @client.notes = nil
    travel_to @session.ended_at + 50.minutes do
      @session.request_calendar_notes_sync!
      @job.perform(@session.id)
    end
    assert_equal @session.ended_at + 1.hour, @transcript.reload.calendar_notes_next_attempt_at
  end
end
