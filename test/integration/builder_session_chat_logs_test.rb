require "test_helper"

class BuilderSessionChatLogsTest < ActionDispatch::IntegrationTest
  setup do
    @facilitator = User.create!(email: "facilitator@example.com", name: "Facilitator", facilitator: true, verified_at: Time.current)
    @builder = User.create!(email: "builder@example.com", name: "Builder", enrollment_status: "active", verified_at: Time.current)
    @outsider = User.create!(email: "outsider@example.com", verified_at: Time.current)
    program = Program.create!(name: "Continuous", starts_on: Date.new(2026, 8, 20), ends_on: Date.new(2026, 12, 17), capacity: 9, main_facilitator: @facilitator)
    @session = program.builder_sessions.create!(
      assigned_facilitator: @facilitator, google_event_id: "weekly", title: "Weekly builders",
      scheduled_starts_at: 1.day.ago, scheduled_ends_at: 1.day.ago + 90.minutes,
      time_zone: "Europe/Berlin", state: "completed"
    )
    @session.create_transcript!
  end

  test "facilitators can save and correct manual chat without touching transcript content" do
    sign_in_as(@facilitator)

    post builder_session_chat_log_path(@session), params: chat_params("15:40 Builder: My link is ready.")
    assert_redirected_to @session
    assert_equal "15:40 Builder: My link is ready.", @session.reload.chat_log.content
    assert_equal "manual", @session.chat_log.source
    assert_equal "pending", @session.transcript.state
    assert_equal "[FILTERED]", request.filtered_parameters["builder_session_chat_log"]

    patch builder_session_chat_log_path(@session), params: chat_params("The complete corrected chat.")
    assert_redirected_to @session
    assert_equal "The complete corrected chat.", @session.chat_log.reload.content
    assert_equal 1, BuilderSessionChatLog.count
  end

  test "unauthenticated users inactive users and active builders cannot save chat" do
    post builder_session_chat_log_path(@session), params: chat_params("Anonymous")
    assert_redirected_to sign_in_path
    sign_in_as(@outsider)
    post builder_session_chat_log_path(@session), params: chat_params("Outsider")
    assert_redirected_to dashboard_path
    sign_in_as(@builder)
    post builder_session_chat_log_path(@session), params: chat_params("Builder")
    assert_redirected_to builder_sessions_path
    assert_nil @session.reload.chat_log
  end

  test "chat cannot be saved for live or deleted session records and invalid input is harmless" do
    sign_in_as(@facilitator)
    @session.update!(state: "ready")
    post builder_session_chat_log_path(@session), params: chat_params("Too early")
    assert_nil @session.reload.chat_log
    @session.update!(state: "completed")
    post builder_session_chat_log_path(@session), params: chat_params("a" * (1.megabyte + 1))
    assert_nil @session.reload.chat_log
    post builder_session_chat_log_path(@session), params: {}
    assert_redirected_to @session
    post builder_session_chat_log_path(@session), params: chat_params([ "Not scalar content" ])
    assert_redirected_to @session
    assert_nil @session.reload.chat_log
    @session.transcript.delete_content!
    post builder_session_chat_log_path(@session), params: chat_params("Deleted record")
    assert_nil @session.reload.chat_log
  end

  private

  def chat_params(content)
    { builder_session_chat_log: { content: content, source: "google_chat" } }
  end

  def sign_in_as(user)
    token = user.generate_token_for(:email_verification)
    post verify_email_path, params: { token: token }
  end
end
