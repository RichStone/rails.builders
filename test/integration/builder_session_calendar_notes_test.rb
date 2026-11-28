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

  private

  def sign_in_as(user)
    delete sign_out_path
    token = user.generate_token_for(:email_verification)
    post verify_email_path, params: { token: token }
  end
end
