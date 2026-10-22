require "test_helper"

class SessionCancellationsTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  setup do
    travel_to Time.utc(2026, 10, 20, 12)
    @facilitator = User.create!(
      email: "facilitator@example.com", name: "Session Facilitator", facilitator: true,
      enrollment_status: "active", verified_at: Time.current
    )
    @builder = User.create!(
      email: "builder@example.com", name: "Active Builder", enrollment_status: "active",
      verified_at: Time.current
    )
    @program = Program.create!(
      name: "Continuous", starts_on: Date.new(2026, 9, 3), ends_on: Date.new(2026, 12, 17),
      main_facilitator: @facilitator
    )
    @program.create_calendar_connection!(
      facilitator: @facilitator, google_account_email: @facilitator.email,
      google_calendar_id: "sessions@group.calendar.google.com",
      google_calendar_name: "Rails.Builders Sessions", oauth_token_json: "{}", status: "connected"
    )
    @builder_session = @program.builder_sessions.create!(
      google_event_id: "weekly-session_20261022T153000Z", title: "Thursday session",
      source_calendar_id: "sessions@group.calendar.google.com",
      scheduled_starts_at: Time.utc(2026, 10, 22, 15, 30),
      scheduled_ends_at: Time.utc(2026, 10, 22, 17), time_zone: "Europe/Amsterdam"
    )
  end

  test "a facilitator confirms one future session and queues its cancellation" do
    following_session = @program.builder_sessions.create!(
      google_event_id: "weekly-session_20261029T163000Z", title: "Next Thursday",
      scheduled_starts_at: Time.utc(2026, 10, 29, 16, 30),
      scheduled_ends_at: Time.utc(2026, 10, 29, 18), time_zone: "Europe/Amsterdam"
    )
    sign_in_as(@facilitator)

    assert_enqueued_with(job: SessionCancellationJob, args: [ @builder_session.id ]) do
      post cancel_builder_session_path(@builder_session), params: cancellation_params
    end

    assert_redirected_to builder_session_path(@builder_session)
    assert_equal "cancelled", @builder_session.reload.state
    assert_equal "Rich has an important appointment he can’t miss.", @builder_session.cancellation_reason
    assert_not_nil @builder_session.cancellation_requested_at
    assert_equal "ready", following_session.reload.state
    follow_redirect!
    assert_select "[data-session-cancellation-status]", text: /Calendar removal is pending/
    assert_select ".session-ready-panel", text: /Session reminders have stopped/
    assert_select ".session-cancellation-panel", count: 0
    assert_select "input[value='Start session']", count: 0
  end

  test "administrators can cancel a session" do
    administrator = User.create!(
      email: "admin@example.com", name: "Administrator", administrator: true,
      enrollment_status: "inactive", verified_at: Time.current
    )
    sign_in_as(administrator)

    post cancel_builder_session_path(@builder_session), params: cancellation_params

    assert_redirected_to builder_session_path(@builder_session)
    assert_equal "cancelled", @builder_session.reload.state
  end

  test "anonymous visitors and ordinary Builders cannot cancel sessions" do
    assert_no_enqueued_jobs(only: SessionCancellationJob) do
      post cancel_builder_session_path(@builder_session), params: cancellation_params
      assert_redirected_to sign_in_path

      sign_in_as(@builder)
      post cancel_builder_session_path(@builder_session), params: cancellation_params
      assert_redirected_to builder_sessions_path
    end

    assert_equal "ready", @builder_session.reload.state
    assert_nil @builder_session.cancellation_requested_at
  end

  test "canceling requires recent authentication" do
    sign_in_as(@facilitator)
    @facilitator.login_sessions.update_all(created_at: 16.minutes.ago)

    assert_no_enqueued_jobs(only: SessionCancellationJob) do
      post cancel_builder_session_path(@builder_session), params: cancellation_params
    end

    assert_redirected_to reauthentication_path
    assert_equal "ready", @builder_session.reload.state
  end

  test "confirmation is required on the server" do
    sign_in_as(@facilitator)

    [ nil, "0", "true" ].each do |confirmation|
      assert_no_enqueued_jobs(only: SessionCancellationJob) do
        post cancel_builder_session_path(@builder_session),
          params: cancellation_params.merge(confirm_cancellation: confirmation)
      end
      assert_redirected_to builder_session_path(@builder_session)
      assert_equal "ready", @builder_session.reload.state
    end
  end

  test "a stale session date and an invalid reason do not cancel anything" do
    sign_in_as(@facilitator)
    stale_params = cancellation_params
    @builder_session.update!(
      scheduled_starts_at: @builder_session.scheduled_starts_at + 1.hour,
      scheduled_ends_at: @builder_session.scheduled_ends_at + 1.hour
    )

    [ stale_params, cancellation_params.merge(cancellation_reason: " ") ].each do |attributes|
      assert_no_enqueued_jobs(only: SessionCancellationJob) do
        post cancel_builder_session_path(@builder_session), params: attributes
      end
      assert_redirected_to builder_session_path(@builder_session)
      assert_equal "ready", @builder_session.reload.state
      assert_nil @builder_session.cancellation_requested_at
    end
  end

  test "a repeated confirmation does not enqueue another cancellation or change the reason" do
    sign_in_as(@facilitator)
    post cancel_builder_session_path(@builder_session), params: cancellation_params

    assert_no_enqueued_jobs(only: SessionCancellationJob) do
      post cancel_builder_session_path(@builder_session),
        params: cancellation_params.merge(cancellation_reason: "A different reason")
    end

    assert_redirected_to builder_session_path(@builder_session)
    assert_equal "Rich has an important appointment he can’t miss.", @builder_session.reload.cancellation_reason
    assert_equal 2, @builder_session.cancellation_deliveries.count
  end

  test "a queue failure leaves the cancellation saved for the recurring retry" do
    sign_in_as(@facilitator)
    failure = ->(*) { raise ActiveJob::EnqueueError, "Queue unavailable" }

    with_stubbed_singleton_method(SessionCancellationJob, :perform_later, failure) do
      post cancel_builder_session_path(@builder_session), params: cancellation_params
    end

    assert_redirected_to builder_session_path(@builder_session)
    assert_equal "cancelled", @builder_session.reload.state
    assert_not_nil @builder_session.cancellation_requested_at
    assert_nil @builder_session.cancellation_completed_at
  end

  test "only operators see the dated cancellation confirmation for future ready sessions" do
    sign_in_as(@builder)
    get builder_session_path(@builder_session)
    assert_select ".session-cancellation-panel", count: 0

    delete sign_out_path
    sign_in_as(@facilitator)
    get builder_session_path(@builder_session)
    assert_select ".session-cancellation-panel summary", text: "☢ Cancel session"
    assert_select ".session-cancellation-panel h2", text: "Cancel Thursday 22 October 2026 at 17:30 CEST?"
    assert_select "form[action='#{cancel_builder_session_path(@builder_session)}']" do
      assert_select "textarea[name='cancellation_reason'][required][maxlength='500']", text: ""
      assert_select "input[name='confirm_cancellation'][type='checkbox'][required]"
      assert_select "input[name='expected_scheduled_starts_at'][value='#{@builder_session.scheduled_starts_at.iso8601(6)}']"
    end

    @builder_session.update!(scheduled_starts_at: 2.hours.ago, scheduled_ends_at: 1.hour.ago)
    get builder_session_path(@builder_session)
    assert_select ".session-cancellation-panel", count: 0
  end

  test "operators see progress while Builders see that reminders stopped" do
    @builder_session.request_cancellation!(
      reason: cancellation_params[:cancellation_reason],
      expected_scheduled_starts_at: @builder_session.scheduled_starts_at.iso8601(6)
    )
    sign_in_as(@facilitator)
    @builder_session.update!(cancellation_calendar_deleted_at: Time.current)
    get builder_session_path(@builder_session)
    assert_select "[data-session-cancellation-status]", text: /Cancellation emails are pending/

    @builder_session.update!(cancellation_completed_at: Time.current)
    get builder_session_path(@builder_session)
    assert_select "[data-session-cancellation-status]", text: /Calendar removal and cancellation notifications are complete/

    delete sign_out_path
    sign_in_as(@builder)
    get builder_session_path(@builder_session)
    assert_select ".session-ready-panel", text: /Session reminders have stopped/
    assert_select "[data-session-cancellation-status]", count: 0
  end

  test "an uncertain email needs an Administrator check after automatic retries expire" do
    @builder_session.request_cancellation!(
      reason: cancellation_params[:cancellation_reason],
      expected_scheduled_starts_at: @builder_session.scheduled_starts_at.iso8601(6)
    )
    @builder_session.update!(cancellation_calendar_deleted_at: Time.current)
    @builder_session.cancellation_deliveries.first.update!(first_attempted_at: 23.hours.ago)
    sign_in_as(@facilitator)

    get builder_session_path(@builder_session)

    assert_select "[data-session-cancellation-status]", text: /Some emails need an Administrator to check delivery before retrying/
    assert_select "[data-session-cancellation-status]", text: /will retry automatically/, count: 0
  end

  test "pending Calendar removal asks an Administrator to reconnect when automatic progress is blocked" do
    @builder_session.request_cancellation!(
      reason: cancellation_params[:cancellation_reason],
      expected_scheduled_starts_at: @builder_session.scheduled_starts_at.iso8601(6)
    )
    sign_in_as(@facilitator)
    connection = @program.calendar_connection

    [
      { status: "reauthorization_required" },
      { status: "authorizing" },
      { status: "connected", google_calendar_id: "different@group.calendar.google.com" }
    ].each do |attributes|
      connection.update!(attributes)
      get builder_session_path(@builder_session)
      assert_select "[data-session-cancellation-status]", text: /reconnect the original Calendar before continuing/
      assert_select "[data-session-cancellation-status]", text: /will retry automatically/, count: 0
    end

    connection.destroy!
    get builder_session_path(@builder_session)
    assert_select "[data-session-cancellation-status]", text: /reconnect the original Calendar before continuing/
    assert_select "[data-session-cancellation-status]", text: /will retry automatically/, count: 0
  end

  test "a session without a confirmed Calendar source cannot be canceled and explains the sync requirement" do
    sign_in_as(@facilitator)

    [ nil, "different@group.calendar.google.com" ].each do |source_calendar_id|
      @builder_session.update!(source_calendar_id:)
      get builder_session_path(@builder_session)
      assert_select ".session-cancellation-panel .form-warning", text: /Sync the selected Calendar before canceling/

      assert_no_enqueued_jobs(only: SessionCancellationJob) do
        post cancel_builder_session_path(@builder_session), params: cancellation_params
      end
      assert_redirected_to builder_session_path(@builder_session)
      assert_equal "ready", @builder_session.reload.state
      assert_match(/sync its original Calendar/, flash[:alert])
    end
  end

  private

  def cancellation_params
    {
      cancellation_reason: "Rich has an important appointment he can’t miss.",
      confirm_cancellation: "1",
      expected_scheduled_starts_at: @builder_session.scheduled_starts_at.iso8601(6)
    }
  end

  def sign_in_as(user)
    token = user.reload.generate_token_for(:email_verification)
    get verify_email_path(token: token)
    post verify_email_path, params: { token: token }
  end
end
