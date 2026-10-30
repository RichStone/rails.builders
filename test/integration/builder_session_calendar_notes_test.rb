require "test_helper"

class BuilderSessionCalendarNotesTest < ActionDispatch::IntegrationTest
  setup do
    travel_to Time.utc(2026, 10, 29, 19)
    @facilitator = User.create!(email: "facilitator@example.com", name: "Facilitator", facilitator: true, verified_at: Time.current)
    @administrator = User.create!(email: "administrator@example.com", name: "Administrator", administrator: true, verified_at: Time.current)
    @builder = User.create!(email: "builder@example.com", name: "Builder", enrollment_status: "active", verified_at: Time.current)
    @outsider = User.create!(email: "outsider@example.com", verified_at: Time.current)
    @program = Program.create!(name: "Continuous", starts_on: Date.new(2026, 8, 20), ends_on: Date.new(2026, 12, 17), capacity: 9, main_facilitator: @facilitator)
    @session = @program.builder_sessions.create!(
      assigned_facilitator: @facilitator, google_event_id: "weekly", title: "Weekly builders",
      scheduled_starts_at: 3.hours.ago, scheduled_ends_at: 2.hours.ago,
      started_at: 3.hours.ago, ended_at: 2.hours.ago,
      time_zone: "Europe/Madrid", state: "completed", facilitator_name_snapshot: "Facilitator"
    )
    @session.create_transcript!
  end

  test "facilitators and administrators can queue notes from the session page" do
    [ @facilitator, @administrator ].each do |operator|
      sign_in_as(operator)
      get builder_session_path(@session)
      assert_select "form[action='#{sync_notes_builder_session_path(@session)}'] button", text: "Sync notes from calendar invite"

      assert_enqueued_with(job: GoogleCalendarNotesSyncJob, args: [ @session.id ]) do
        post sync_notes_builder_session_path(@session)
      end
      assert_redirected_to @session
      assert_equal Time.current, @session.reload.transcript.calendar_notes_next_attempt_at
      assert_equal "pending", @session.transcript.state
      follow_redirect!
      assert_select "[data-calendar-notes-status]", text: /Calendar notes sync queued/
    end
  end

  test "anonymous inactive and active builders cannot request notes sync" do
    assert_no_enqueued_jobs only: GoogleCalendarNotesSyncJob do
      post sync_notes_builder_session_path(@session)
      assert_redirected_to sign_in_path

      sign_in_as(@outsider)
      post sync_notes_builder_session_path(@session)
      assert_redirected_to dashboard_path
      get builder_session_path(@session)
      assert_redirected_to dashboard_path

      sign_in_as(@builder)
      post sync_notes_builder_session_path(@session)
      assert_redirected_to builder_sessions_path
      get builder_session_path(@session)
      assert_select "form[action='#{sync_notes_builder_session_path(@session)}']", count: 0
    end
    assert_nil @session.reload.transcript.calendar_notes_next_attempt_at
  end

  test "notes sync and viewing stay within the current program" do
    other_program = Program.create!(name: "Other", starts_on: Date.new(2026, 8, 20), ends_on: Date.new(2026, 12, 17), capacity: 9)
    @session.update!(program: other_program)
    @session.transcript.update!(calendar_notes: "PRIVATE OTHER PROGRAM NOTES")
    sign_in_as(@facilitator)

    assert_no_enqueued_jobs only: GoogleCalendarNotesSyncJob do
      post sync_notes_builder_session_path(@session)
      assert_response :not_found
    end
    get builder_session_path(@session)
    assert_response :not_found
    assert_select "[data-calendar-notes-content]", count: 0
  end

  test "unfinished and deleted records cannot sync notes or show the sync button" do
    sign_in_as(@facilitator)

    %w[ready connection cancelled].each do |state|
      @session.update!(state: state)
      assert_no_enqueued_jobs only: GoogleCalendarNotesSyncJob do
        post sync_notes_builder_session_path(@session)
      end
      assert_redirected_to @session
      get builder_session_path(@session)
      assert_select "[data-session-calendar-notes]", count: 0
    end

    @session.update!(state: "completed")
    @session.transcript.update!(calendar_notes: "PRIVATE DELETED NOTES")
    @session.transcript.delete_content!
    assert_no_enqueued_jobs only: GoogleCalendarNotesSyncJob do
      post sync_notes_builder_session_path(@session)
    end
    assert_redirected_to @session
    get builder_session_path(@session)
    assert_select "[data-session-calendar-notes]", count: 0
    assert_not_includes response.body, "PRIVATE DELETED NOTES"
    assert_equal "deleted", @session.reload.transcript.state
  end

  test "calendar notes are readable and sanitized before a transcript arrives and remain separate afterwards" do
    transcript = @session.transcript
    transcript.update!(
      calendar_notes: "## Full notes\n\nA useful session.\n\n[Source document](https://docs.google.com/document/d/source-notes/edit)\n\n<script>alert('notes')</script>\n\n[steal](javascript:alert('x'))\n\n![tracking](https://example.com/tracking.png)",
      calendar_notes_synced_at: Time.current
    )
    sign_in_as(@builder)

    get builder_session_path(@session)
    assert_response :success
    assert_equal "no-store", response.headers["Cache-Control"]
    assert_select "[data-calendar-notes-content] h2", text: "Full notes"
    assert_select "[data-calendar-notes-content] a[href='https://docs.google.com/document/d/source-notes/edit']", text: "Source document"
    assert_select "[data-calendar-notes-content] script", count: 0
    assert_select "[data-calendar-notes-content] img", count: 0
    assert_select "[data-calendar-notes-content] a[href^='javascript:']", count: 0
    assert_select "details[data-calendar-notes-document]:not([open])"
    assert_select "[data-calendar-notes-status]", text: /Last synced 29 October 2026 at 20:00 CET/
    assert_select ".transcript-processing", text: /Processing transcript/

    transcript.replace_with_manual!("Spoken transcript", summary_notes: "Manually curated notes")
    get builder_session_path(@session)
    assert_select "[data-calendar-notes-content]", text: /A useful session/
    assert_select "[data-session-notes-content]", text: "Manually curated notes"
    assert_select "[data-session-transcript-content]", text: /Spoken transcript/

    get root_path
    assert_not_includes response.body, "A useful session"
    assert_not_includes response.body, "source-notes"
  end

  test "notes sync can create its record without requiring a transcript" do
    @session.transcript.destroy!
    @session.reload
    sign_in_as(@facilitator)

    assert_difference "BuilderSessionTranscript.count", 1 do
      assert_enqueued_with(job: GoogleCalendarNotesSyncJob, args: [ @session.id ]) do
        post sync_notes_builder_session_path(@session)
      end
    end
    assert_nil @session.reload.transcript.content
    assert_not_equal "ready", @session.transcript.state
  end

  test "notes failures offer a safe permission remedy without exposing provider errors" do
    @session.transcript.update!(calendar_notes_error_code: "GoogleNotesPermissionRequired")
    sign_in_as(@administrator)
    get builder_session_path(@session)
    assert_select "[data-calendar-notes-status]", text: /Allow read-only Google Docs access/
    assert_select "[data-calendar-notes-status] a[href='#{admin_root_path}']", text: "Administration"

    sign_in_as(@facilitator)
    get builder_session_path(@session)
    assert_select "[data-calendar-notes-status]", text: /Ask an Administrator/
    assert_select "[data-calendar-notes-status] a[href='#{admin_root_path}']", count: 0

    @session.transcript.update!(calendar_notes_error_code: "UnexpectedProviderFailure")
    get builder_session_path(@session)
    assert_select "[data-calendar-notes-status]", text: /Meeting notes could not be synced. Try again./
    assert_not_includes response.body, "UnexpectedProviderFailure"
  end

  private

  def sign_in_as(user)
    delete sign_out_path
    token = user.generate_token_for(:email_verification)
    post verify_email_path, params: { token: token }
  end
end
