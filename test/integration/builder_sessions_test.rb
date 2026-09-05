require "test_helper"

class BuilderSessionsTest < ActionDispatch::IntegrationTest
  setup do
    @facilitator = User.create!(
      email: "facilitator@example.com",
      name: "Main Facilitator",
      facilitator: true,
      enrollment_status: "active",
      verified_at: Time.current
    )
    @builder = User.create!(
      email: "builder@example.com",
      name: "Active Builder",
      enrollment_status: "active",
      verified_at: Time.current
    )
    @waitlisted = User.create!(
      email: "waiting@example.com",
      name: "Waiting Builder",
      enrollment_status: "waitlisted",
      waitlist_rank: 1,
      waitlist_joined_at: Time.current,
      verified_at: Time.current
    )
    @program = Program.create!(
      name: "Continuous",
      starts_on: Date.new(2026, 8, 20),
      ends_on: Date.new(2026, 12, 17),
      capacity: 9,
      main_facilitator: @facilitator
    )
    @builder_session = @program.builder_sessions.create!(
      assigned_facilitator: @facilitator,
      google_event_id: "calendar-event-1",
      title: "Product teardown",
      description: "A focused session. Join at https://meet.google.com/private-code",
      meet_url: "https://meet.google.com/abc-defg-hij",
      scheduled_starts_at: Time.zone.parse("2026-08-24 18:00"),
      scheduled_ends_at: Time.zone.parse("2026-08-24 19:00"),
      time_zone: "Europe/Madrid"
    )
  end

  test "the homepage shows an upcoming session without private session data" do
    @builder_session.update!(
      title: "Product teardown · meet.google.com/abc-defg-hij",
      scheduled_starts_at: 1.day.from_now,
      scheduled_ends_at: 1.day.from_now + 90.minutes
    )
    @builder_session.create_transcript!(
      state: "ready",
      source: "manual",
      content: "PRIVATE TRANSCRIPT",
      summary_notes: "PRIVATE SUMMARY NOTES",
      session_analysis: "PRIVATE SESSION ANALYSIS"
    )

    get root_path

    assert_response :success
    assert_select "[data-public-sessions]", text: /Product teardown/
    assert_select "[data-public-sessions]", text: /Facilitated by Rails Builders/
    assert_select "[data-public-sessions]", text: /60-minute core session/
    assert_select "[data-public-sessions]", text: /90 minutes/, count: 0
    assert_not_includes response.body, "Main Facilitator"
    assert_not_includes response.body, "abc-defg-hij"
    assert_not_includes response.body, "private-code"
    assert_not_includes response.body, @builder.email
    assert_not_includes response.body, "PRIVATE TRANSCRIPT"
    assert_not_includes response.body, "PRIVATE SUMMARY NOTES"
    assert_not_includes response.body, "PRIVATE SESSION ANALYSIS"
  end

  test "the public live banner does not reveal private people or meeting links" do
    @builder_session.update!(title: "Live teardown · https://meet.google.com/abc-defg-hij")
    @builder_session.start!(facilitator: @facilitator)

    get root_path

    assert_select ".live-session-banner", text: /Live now/
    assert_select ".live-session-banner", text: /Facilitated by Rails Builders/
    assert_select ".live-session-banner a", count: 0
    public_sessions = css_select("[data-public-sessions]").to_s
    assert_not_includes public_sessions, "abc-defg-hij"
    assert_not_includes public_sessions, "Main Facilitator"
    assert_not_includes public_sessions, "Active Builder"
  end

  test "active Builders can see private session details" do
    starts_at = 1.day.from_now
    @builder_session.update!(scheduled_starts_at: starts_at, scheduled_ends_at: starts_at + 90.minutes)
    sign_in_as(@builder)

    get builder_sessions_path
    assert_response :success
    assert_select "a", text: "Product teardown"
    assert_select ".session-list-item > span", text: "60 min core"
    assert_select ".session-list-item > span", text: "90 min", count: 0

    get builder_session_path(@builder_session)
    assert_response :success
    assert_equal "no-store", response.headers["Cache-Control"]
    assert_select "meta[name='turbo-cache-control'][content='no-cache']"
    assert_select "a[href='#{join_builder_session_path(@builder_session)}']", text: /Join Google Meet/
    assert_select ".privacy-note", text: /recorded or transcribed.*AI-generated notes.*trend analysis/i
    assert_select ".privacy-note a[href='#{privacy_path}']", text: "Privacy details"
    assert_select "[data-session-controls]", count: 0
    assert_select ".attendance-row", text: /Active Builder.*Attending/m
    assert_select "form[action='#{attendance_builder_session_path(@builder_session)}']", count: 0

    get join_builder_session_path(@builder_session)
    assert_redirected_to "https://meet.google.com/abc-defg-hij"
    assert_equal "no-store", response.headers["Cache-Control"]
    assert_equal "[FILTERED]", response.filtered_location
  end

  test "the ready session shows every Active Builder regardless of public profile" do
    @builder.update!(public_profile: false, public_profile_approved: false)
    sign_in_as(@facilitator)

    get builder_session_path(@builder_session)

    assert_response :success
    assert_select ".attendance-panel", text: /Expected attendance/
    assert_select ".attendance-row", text: /Active Builder.*Attending/m
    assert_select ".attendance-row", text: /Waiting Builder/, count: 0
    assert_select "form[action='#{attendance_builder_session_path(@builder_session)}']" do
      assert_select "button", text: "Mark not attending"
    end
  end

  test "facilitators can change expected attendance repeatedly before the session starts" do
    sign_in_as(@facilitator)

    2.times do
      patch attendance_builder_session_path(@builder_session), params: { user_id: @builder.id, status: "present" }
      follow_redirect!
      assert_select ".attendance-row", text: /Active Builder.*Attending/m

      patch attendance_builder_session_path(@builder_session), params: { user_id: @builder.id, status: "absent" }
      follow_redirect!
      assert_select ".attendance-row", text: /Active Builder.*Not attending/m
    end

    patch attendance_builder_session_path(@builder_session), params: { user_id: @builder.id, status: "present" }
    post start_builder_session_path(@builder_session), params: { duration_minutes: 30 }
    follow_redirect!

    assert_select ".attendance-row", text: /Active Builder.*Present/m
    assert_nil @builder_session.attendances.find_by!(user: @builder).arrived_at
  end

  test "facilitators configure every phase and can discard a mistaken start" do
    @builder_session.update!(
      scheduled_starts_at: 2.hours.from_now,
      scheduled_ends_at: 3.hours.from_now
    )
    sign_in_as(@facilitator)

    get builder_session_path(@builder_session)

    assert_select ".session-ready-panel", text: /outside the scheduled start window/i
    assert_select "form[action='#{start_builder_session_path(@builder_session)}'][data-turbo='false']" do
      assert_select "[data-turbo-confirm]", count: 0
      assert_select "input[name='pre_core_minutes'][value='10']"
      assert_select "input[name='duration_minutes'][value='30']"
      assert_select "input[name='hangout_minutes'][value='30']"
    end

    post start_builder_session_path(@builder_session), params: {
      pre_core_minutes: 5,
      duration_minutes: 20,
      hangout_minutes: 10
    }

    assert_redirected_to builder_session_path(@builder_session)
    assert_equal "connection", @builder_session.reload.state
    assert_equal 5.minutes.to_i, @builder_session.pre_core_duration_seconds
    assert_equal 20.minutes.to_i, @builder_session.timer_duration_seconds
    assert_equal 10.minutes.to_i, @builder_session.hangout_duration_seconds

    get builder_session_path(@builder_session)
    assert_select ".live-phase", text: /Pre-core/i
    assert_select "form[action='#{cancel_start_builder_session_path(@builder_session)}']" do
      assert_select "input[name='run_started_at'][value='#{@builder_session.started_at.iso8601(6)}']"
      assert_select "button", text: "Discard session run"
    end

    post cancel_start_builder_session_path(@builder_session), params: {
      run_started_at: @builder_session.started_at.iso8601(6)
    }

    assert_redirected_to builder_session_path(@builder_session)
    assert_equal "ready", @builder_session.reload.state
    assert_nil @builder_session.transcript
  end

  test "a stale finish submission cannot complete a newer timer run" do
    first_start = Time.zone.parse("2026-08-24 18:00")
    travel_to(first_start) { @builder_session.start!(facilitator: @facilitator) }
    @builder_session.finish_current_speaker!(at: first_start + 1.minute)
    first_run = @builder_session.started_at.iso8601(6)
    assert @builder_session.cancel_start!(expected_started_at: first_run)

    second_start = first_start + 2.minutes
    travel_to(second_start) { @builder_session.start!(facilitator: @facilitator) }
    @builder_session.finish_current_speaker!(at: second_start + 1.minute)
    second_run = @builder_session.started_at.iso8601(6)
    sign_in_as(@facilitator)

    post finish_builder_session_path(@builder_session), params: { run_started_at: first_run }

    assert_redirected_to builder_session_path(@builder_session)
    assert_equal "hangout", @builder_session.reload.state
    assert_nil @builder_session.transcript

    post finish_builder_session_path(@builder_session), params: { run_started_at: second_run }

    assert_equal "completed", @builder_session.reload.state
    assert @builder_session.transcript
  end

  test "stale live controls cannot mutate a replacement timer run" do
    User.create!(email: "second@example.com", name: "Second Builder", enrollment_status: "active", verified_at: Time.current)
    User.create!(email: "third@example.com", name: "Third Builder", enrollment_status: "active", verified_at: Time.current)
    first_start = Time.zone.parse("2026-08-24 18:00")
    travel_to(first_start) { @builder_session.start!(facilitator: @facilitator, pre_core_duration_seconds: 5.minutes.to_i) }
    first_run = @builder_session.run_token
    assert @builder_session.cancel_start!(expected_started_at: first_run)
    sign_in_as(@facilitator)

    patch attendance_builder_session_path(@builder_session),
      params: { user_id: @builder.id, status: "absent", run_started_at: first_run }
    assert_equal "present", @builder_session.reload.attendances.find_by!(user: @builder).status

    travel_to(first_start + 2.minutes) do
      @builder_session.start!(facilitator: @facilitator, pre_core_duration_seconds: 5.minutes.to_i)
    end
    second_run = @builder_session.run_token

    post pause_builder_session_path(@builder_session), params: { run_started_at: first_run }
    assert_not @builder_session.reload.paused?
    post pause_builder_session_path(@builder_session), params: { run_started_at: second_run }
    assert @builder_session.reload.paused?

    post resume_builder_session_path(@builder_session), params: { run_started_at: first_run }
    assert @builder_session.reload.paused?
    post resume_builder_session_path(@builder_session), params: { run_started_at: second_run }
    assert_not @builder_session.reload.paused?

    post advance_builder_session_path(@builder_session), params: { state: "connection", run_started_at: first_run }
    assert_equal "connection", @builder_session.reload.state
    post advance_builder_session_path(@builder_session), params: { state: "connection", run_started_at: second_run }
    assert_equal "builder_updates", @builder_session.reload.state

    current_speaker = @builder_session.current_speaker_attendance
    patch attendance_builder_session_path(@builder_session),
      params: { user_id: current_speaker.user_id, status: "absent", run_started_at: first_run }
    assert_equal "present", current_speaker.reload.status
    assert_equal current_speaker, @builder_session.reload.current_speaker_attendance

    original_order = @builder_session.unspoken_speakers.pluck(:id)
    patch speaker_order_builder_session_path(@builder_session),
      params: { attendance_ids: original_order.reverse, run_started_at: first_run },
      as: :json
    assert_response :conflict
    assert_equal original_order, @builder_session.reload.unspoken_speakers.pluck(:id)

    post next_speaker_builder_session_path(@builder_session),
      params: { speaker_id: current_speaker.id, run_started_at: first_run }
    assert_equal current_speaker, @builder_session.reload.current_speaker_attendance
  end

  test "invalid phase lengths never start a session" do
    sign_in_as(@facilitator)

    [
      { pre_core_minutes: "nope", duration_minutes: 20, hangout_minutes: 10 },
      { pre_core_minutes: 100, duration_minutes: 200, hangout_minutes: 1 },
      { pre_core_minutes: 10, duration_minutes: 0, hangout_minutes: 10 },
      { pre_core_minutes: 10, duration_minutes: 20, hangout_minutes: -1 }
    ].each do |phase_lengths|
      post start_builder_session_path(@builder_session), params: phase_lengths

      assert_redirected_to builder_session_path(@builder_session)
      assert_equal "ready", @builder_session.reload.state
      assert_equal "Choose valid session phase lengths.", flash[:alert]
    end
  end

  test "Builders cannot discard an active timer run" do
    @builder_session.start!(facilitator: @facilitator)
    run_started_at = @builder_session.started_at.iso8601(6)
    sign_in_as(@builder)

    post cancel_start_builder_session_path(@builder_session), params: { run_started_at: }

    assert_redirected_to builder_sessions_path
    assert_equal "builder_updates", @builder_session.reload.state
  end

  test "cancelled and completed sessions cannot be joined" do
    sign_in_as(@builder)

    @builder_session.update!(state: "cancelled")
    get builder_session_path(@builder_session)
    assert_select "a", text: /Join Google Meet/, count: 0
    get join_builder_session_path(@builder_session)
    assert_redirected_to builder_session_path(@builder_session)

    @builder_session.update!(state: "ready")
    @builder_session.start!(facilitator: @facilitator)
    @builder_session.finish!
    get builder_session_path(@builder_session)
    assert_select "a", text: /Join Google Meet/, count: 0
    get join_builder_session_path(@builder_session)
    assert_redirected_to builder_session_path(@builder_session)
  end

  test "the completed-session summary reports core time without the optional hangout" do
    started_at = Time.zone.parse("2026-08-24 18:00")
    @builder_session.update!(
      state: "completed",
      started_at:,
      hangout_started_at: started_at + 60.minutes,
      ended_at: started_at + 90.minutes,
      facilitator_name_snapshot: @facilitator.name
    )
    sign_in_as(@builder)

    get builder_session_path(@builder_session)

    assert_select ".session-complete-panel", text: /60-minute core session/
    assert_select ".session-complete-panel", text: /90 minutes/, count: 0
  end

  test "facilitators can correct completed start and end times while attendance stays editable" do
    original_start = ActiveSupport::TimeZone["Europe/Madrid"].parse("2026-08-24 18:00")
    @builder_session.update!(
      state: "completed",
      started_at: original_start,
      hangout_started_at: original_start + 45.minutes,
      ended_at: original_start + 75.minutes,
      finish_reason: "manual",
      facilitator_name_snapshot: @facilitator.name
    )
    @builder_session.attendances.create!(user: @builder, display_name: @builder.name, role: "builder", status: "present")
    sign_in_as(@facilitator)

    get builder_session_path(@builder_session)

    assert_select "form[action='#{timing_builder_session_path(@builder_session)}']" do
      assert_select "input[name='started_at']"
      assert_select "input[name='ended_at']"
      assert_select "input[type='submit'][value='Correct session times']"
    end
    assert_select "form[action='#{attendance_builder_session_path(@builder_session)}'] button", text: "Mark absent"

    patch timing_builder_session_path(@builder_session), params: {
      started_at: "2026-08-24T17:55",
      ended_at: "2026-08-24T19:20"
    }

    assert_redirected_to builder_session_path(@builder_session)
    assert_equal original_start - 5.minutes, @builder_session.reload.started_at
    assert_equal original_start + 80.minutes, @builder_session.ended_at
  end

  test "the correction form preserves recorded seconds in its own submitted values" do
    zone = ActiveSupport::TimeZone["Europe/Madrid"]
    started_at = zone.parse("2026-08-24 18:00:05") + 0.2.seconds
    displayed_start = zone.parse("2026-08-24 18:00:05")
    displayed_end = zone.parse("2026-08-24 18:46:00")
    @builder_session.update!(
      state: "completed",
      started_at:,
      builder_updates_started_at: started_at + 0.6.seconds,
      hangout_started_at: displayed_end + 0.2.seconds,
      ended_at: displayed_end + 0.7.seconds,
      facilitator_name_snapshot: @facilitator.name
    )
    sign_in_as(@facilitator)

    get builder_session_path(@builder_session)

    assert_select "input[name='started_at'][value='2026-08-24T18:00:05'][step='1']"
    assert_select "input[name='ended_at'][value='2026-08-24T18:46:00'][step='1']"

    patch timing_builder_session_path(@builder_session), params: {
      started_at: "2026-08-24T18:00:05",
      ended_at: "2026-08-24T18:46:00"
    }

    assert_redirected_to builder_session_path(@builder_session)
    assert_equal displayed_start, @builder_session.reload.started_at
    assert_equal displayed_end, @builder_session.ended_at
  end

  test "a missed ready session appears in Past instead of Upcoming" do
    sign_in_as(@builder)

    travel_to(@builder_session.scheduled_starts_at + 1.minute) do
      get builder_sessions_path
    end

    sections = css_select("section.session-section")
    upcoming = sections.find { |section| section.at_css("h2")&.text == "Upcoming" }
    past = sections.find { |section| section.at_css("h2")&.text == "Past" }
    assert_not_includes upcoming.text, "Product teardown"
    assert_includes past.text, "Product teardown"
  end

  test "visitors and waitlisted users cannot open private sessions" do
    get builder_sessions_path
    assert_redirected_to sign_in_path

    sign_in_as(@waitlisted)
    get builder_sessions_path
    assert_redirected_to dashboard_path
  end

  test "facilitators operate attendance and the live session while Builders can only view" do
    sign_in_as(@builder)
    post start_builder_session_path(@builder_session), params: { duration_minutes: 45 }
    assert_redirected_to builder_sessions_path
    assert_equal "ready", @builder_session.reload.state

    delete sign_out_path
    sign_in_as(@facilitator)
    post start_builder_session_path(@builder_session), params: { duration_minutes: 45 }
    assert_redirected_to builder_session_path(@builder_session)
    assert_equal "builder_updates", @builder_session.reload.state
    assert_equal 45.minutes.to_i, @builder_session.timer_duration_seconds
    run_started_at = @builder_session.run_token

    get builder_session_path(@builder_session)
    assert_select "[data-controller='session-timer']"
    assert_select "[data-session-controls]"
    assert_select "form[action='#{pause_builder_session_path(@builder_session)}']"

    patch attendance_builder_session_path(@builder_session), params: { user_id: @builder.id, status: "present", run_started_at: }
    assert_equal "present", @builder_session.attendances.find_by!(user: @builder).status

    post pause_builder_session_path(@builder_session), params: { run_started_at: }
    assert @builder_session.paused?
    post resume_builder_session_path(@builder_session), params: { run_started_at: }
    assert_not @builder_session.paused?
    speaker_id = @builder_session.current_speaker_attendance.id
    post next_speaker_builder_session_path(@builder_session), params: { speaker_id:, run_started_at: }
    assert_equal "hangout", @builder_session.reload.state
    post finish_builder_session_path(@builder_session), params: { run_started_at: @builder_session.started_at.iso8601(6) }
    assert_equal "completed", @builder_session.reload.state
  end

  test "repeated speaker and core-finish submissions do not skip ahead" do
    User.create!(email: "second@example.com", name: "Second Builder", enrollment_status: "active", verified_at: Time.current)
    User.create!(email: "third@example.com", name: "Third Builder", enrollment_status: "active", verified_at: Time.current)
    sign_in_as(@facilitator)
    post start_builder_session_path(@builder_session), params: { duration_minutes: 30 }
    first_speaker_id = @builder_session.reload.current_speaker_attendance.id
    run_started_at = @builder_session.run_token

    2.times do
      post next_speaker_builder_session_path(@builder_session), params: { speaker_id: first_speaker_id, run_started_at: }
    end

    assert_equal "builder_updates", @builder_session.reload.state
    assert_equal 1, @builder_session.attendances.where(speaker_state: "completed").count

    2.times do
      post advance_builder_session_path(@builder_session), params: { state: "builder_updates", run_started_at: }
    end

    assert_equal "hangout", @builder_session.reload.state
    assert_nil @builder_session.ended_at
  end

  test "the facilitator sees a two-thirds timer default and the session prompts" do
    @builder_session.update!(scheduled_ends_at: @builder_session.scheduled_starts_at + 90.minutes)
    sign_in_as(@facilitator)

    get builder_session_path(@builder_session)

    assert_select "label[for='duration_minutes']", text: "Core (minutes)"
    assert_select "input[name='duration_minutes'][value='60']"

    post start_builder_session_path(@builder_session)
    assert_equal 60.minutes.to_i, @builder_session.reload.timer_duration_seconds

    get builder_session_path(@builder_session)
    assert_select ".live-phase", text: /Core session/i

    assert_select "[data-session-prompts]" do
      assert_select "li", text: "One business challenge"
      assert_select "li", text: "One AI-building challenge"
      assert_select "li", text: "What will you have done by the next session?"
    end
  end

  test "the live room shows the shared core-time allocation for every queued Builder" do
    User.create!(email: "second@example.com", name: "Second Builder", enrollment_status: "active", verified_at: Time.current)
    sign_in_as(@facilitator)

    post start_builder_session_path(@builder_session), params: { duration_minutes: 30 }
    follow_redirect!

    assert_select ".live-phase", text: /Core session/i
    assert_select ".speaker-queue .attendance-row", count: 1 do
      assert_select "span", text: /Up next · 15:00 allocated/
    end
  end

  test "facilitators drag the complete unspoken queue into a new order" do
    second_builder = User.create!(email: "second@example.com", name: "Second Builder", enrollment_status: "active", verified_at: Time.current)
    third_builder = User.create!(email: "third@example.com", name: "Third Builder", enrollment_status: "active", verified_at: Time.current)
    @builder_session.start!(facilitator: @facilitator)
    requested_order = @builder_session.unspoken_speakers.pluck(:id).reverse
    sign_in_as(@facilitator)

    get builder_session_path(@builder_session)
    assert_select "[data-controller~='speaker-order']"
    assert_select "[data-speaker-order-target='item']", count: 2

    patch speaker_order_builder_session_path(@builder_session),
      params: { attendance_ids: requested_order, run_started_at: @builder_session.run_token },
      as: :json

    assert_response :success
    assert_equal @builder_session.reload.updated_at.iso8601(6), response.parsed_body.fetch("version")
    assert_equal requested_order, @builder_session.unspoken_speakers.pluck(:id)

    patch speaker_order_builder_session_path(@builder_session),
      params: { attendance_ids: [ requested_order.first, requested_order.first ], run_started_at: @builder_session.run_token },
      as: :json
    assert_response :unprocessable_entity
    assert_equal requested_order, @builder_session.unspoken_speakers.pluck(:id)
  end

  test "Builders see a static queue while Administrators may reorder it" do
    second_builder = User.create!(email: "second@example.com", name: "Second Builder", enrollment_status: "active", verified_at: Time.current)
    third_builder = User.create!(email: "third@example.com", name: "Third Builder", enrollment_status: "active", verified_at: Time.current)
    @builder_session.start!(facilitator: @facilitator)
    original_order = @builder_session.unspoken_speakers.pluck(:id)
    requested_order = original_order.reverse
    sign_in_as(@builder)

    get builder_session_path(@builder_session)
    assert_select "[data-controller~='speaker-order']", count: 0
    assert_select "[draggable='true'][data-action*='speaker-order']", count: 0

    patch speaker_order_builder_session_path(@builder_session),
      params: { attendance_ids: requested_order, run_started_at: @builder_session.run_token },
      as: :json
    assert_redirected_to builder_sessions_path
    assert_equal original_order, @builder_session.unspoken_speakers.pluck(:id)

    delete sign_out_path
    administrator = User.create!(email: "administrator@example.com", name: "Administrator", administrator: true, verified_at: Time.current)
    sign_in_as(administrator)
    patch speaker_order_builder_session_path(@builder_session),
      params: { attendance_ids: requested_order, run_started_at: @builder_session.run_token },
      as: :json

    assert_response :success
    assert_equal requested_order, @builder_session.unspoken_speakers.pluck(:id)
  end

  test "completed transcripts are private, read-only, and support facilitator fallback plus Administrator deletion" do
    travel_to(Time.zone.parse("2026-08-24 18:00")) { @builder_session.start!(facilitator: @facilitator) }
    travel_to(Time.zone.parse("2026-08-24 19:00")) { @builder_session.finish! }
    transcript = @builder_session.reload.transcript

    sign_in_as(@facilitator)
    post builder_session_transcript_path(@builder_session), params: {
      transcript: {
        content: "Ada\n<script>alert('nope')</script>\n<a href='https://example.com'>click</a>\n<img src='/up'>",
        summary_notes: "## Flow summary\n\n- Ada shipped onboarding.\n\n<script>alert('notes')</script>",
        session_analysis: "## Ada\n\n**Current project:** Onboarding\n\n**Latest trend:** Sharper scope.\n\n**What others commented:**\n\n- Yaro: Keep the launch narrow.\n\n[steal](javascript:alert('x'))\n\n<img src='/up'>"
      }
    }
    assert_redirected_to builder_session_path(@builder_session)
    assert_equal "manual", transcript.reload.source
    assert_equal "ready", transcript.state
    assert_equal "## Flow summary\n\n- Ada shipped onboarding.\n\n<script>alert('notes')</script>", transcript.summary_notes
    assert_equal "## Ada\n\n**Current project:** Onboarding\n\n**Latest trend:** Sharper scope.\n\n**What others commented:**\n\n- Yaro: Keep the launch narrow.\n\n[steal](javascript:alert('x'))\n\n<img src='/up'>", transcript.session_analysis
    assert_not_includes transcript.read_attribute_before_type_cast(:summary_notes), "Ada shipped onboarding"
    assert_not_includes transcript.read_attribute_before_type_cast(:session_analysis), "Sharper scope"

    get builder_session_path(@builder_session)
    panels = css_select(".session-record > [data-session-analysis], .session-record > [data-session-notes], .session-record > [data-session-transcript]")
    assert_equal %w[data-session-analysis data-session-notes data-session-transcript], panels.map { |panel| panel.attributes.keys.grep(/^data-session-/).first }
    assert_select "[data-session-analysis] h2", text: "Ada"
    assert_select "[data-session-analysis] strong", text: "Current project:"
    assert_select "[data-session-analysis] li", text: /Keep the launch narrow/
    assert_select "[data-session-analysis] a", count: 0
    assert_select "[data-session-analysis] img", count: 0
    assert_select "details[data-session-notes]:not([open])"
    assert_select "[data-session-notes] h2", text: "Flow summary"
    assert_select "[data-session-notes] li", text: /Ada shipped onboarding/
    assert_select "[data-session-notes] script", count: 0
    assert_select "details[data-session-transcript]:not([open])"
    assert_select "[data-session-transcript]", text: /Ada/
    assert_select "[data-session-transcript] a", count: 0
    assert_select "[data-session-transcript] img", count: 0
    assert_includes response.body, "&lt;script&gt;"
    assert_includes response.body, "&lt;a href="
    assert_includes response.body, "&lt;img src="
    assert_select "textarea[name='transcript[content]']", count: 0
    assert_select "textarea[name='transcript[session_analysis]']", count: 1

    admin = User.create!(email: "admin@example.com", name: "Administrator", administrator: true, verified_at: Time.current)
    delete sign_out_path
    sign_in_as(admin)
    delete builder_session_transcript_path(@builder_session)
    assert_equal "deleted", transcript.reload.state
    assert_nil transcript.content
    assert_nil transcript.summary_notes
    assert_nil transcript.session_analysis
  end

  test "facilitators update notes and analysis without changing a ready transcript while Builders cannot" do
    travel_to(Time.zone.parse("2026-08-24 18:00")) { @builder_session.start!(facilitator: @facilitator) }
    travel_to(Time.zone.parse("2026-08-24 19:00")) { @builder_session.finish! }
    transcript = @builder_session.reload.transcript
    transcript.replace_with_manual!("Original transcript", summary_notes: "Original notes", session_analysis: "## Original")
    sign_in_as(@facilitator)

    patch builder_session_transcript_path(@builder_session), params: {
      transcript: {
        content: "Replacement transcript",
        state: "deleted",
        source: "google",
        summary_notes: "Updated notes",
        session_analysis: "## Updated"
      }
    }

    assert_redirected_to builder_session_path(@builder_session)
    assert_equal "Original transcript", transcript.reload.content
    assert_equal "ready", transcript.state
    assert_equal "manual", transcript.source
    assert_equal "Updated notes", transcript.summary_notes
    assert_equal "## Updated", transcript.session_analysis

    delete sign_out_path
    sign_in_as(@builder)
    patch builder_session_transcript_path(@builder_session), params: {
      transcript: { summary_notes: "Builder notes", session_analysis: "## Builder edit" }
    }

    assert_redirected_to builder_sessions_path
    assert_equal "Updated notes", transcript.reload.summary_notes
    assert_equal "## Updated", transcript.session_analysis

    get builder_session_path(@builder_session)
    assert_select "[data-session-analysis]", text: /Updated/
    assert_select "textarea[name='transcript[session_analysis]']", count: 0
  end

  test "facilitators cannot overwrite ready or deleted transcripts by posting directly" do
    travel_to(Time.zone.parse("2026-08-24 18:00")) { @builder_session.start!(facilitator: @facilitator) }
    travel_to(Time.zone.parse("2026-08-24 19:00")) { @builder_session.finish! }
    transcript = @builder_session.reload.transcript
    transcript.replace_with_manual!("Original notes")
    sign_in_as(@facilitator)

    post builder_session_transcript_path(@builder_session), params: { transcript: { content: "Replacement" } }
    assert_equal "Original notes", transcript.reload.content

    transcript.delete_content!
    post builder_session_transcript_path(@builder_session), params: { transcript: { content: "Resurrected" } }
    assert_equal "deleted", transcript.reload.state
    assert_nil transcript.content

    patch builder_session_transcript_path(@builder_session), params: {
      transcript: { summary_notes: "Restored notes", session_analysis: "## Restored" }
    }
    assert_equal "deleted", transcript.reload.state
    assert_nil transcript.summary_notes
    assert_nil transcript.session_analysis
  end

  test "a manual transcript cannot be attached before a session is completed" do
    sign_in_as(@facilitator)

    post builder_session_transcript_path(@builder_session), params: { transcript: { content: "Too early" } }

    assert_redirected_to builder_session_path(@builder_session)
    assert_not @builder_session.reload.transcript
  end

  test "an unavailable automatic transcript shows a clear private fallback state" do
    travel_to(Time.zone.parse("2026-08-24 18:00")) { @builder_session.start!(facilitator: @facilitator) }
    travel_to(Time.zone.parse("2026-08-24 19:00")) { @builder_session.finish! }
    @builder_session.transcript.update!(state: "unavailable")
    sign_in_as(@builder)

    get builder_session_path(@builder_session)

    assert_select ".transcript-processing", text: /Automatic transcript unavailable/
    assert_select ".manual-transcript", count: 0
    assert_select "[data-controller='session-refresh']", count: 0
  end

  test "facilitators correct an automatic close while Builders cannot change session times" do
    started_at = ActiveSupport::TimeZone["Europe/Madrid"].parse("2026-08-24 18:00")
    travel_to(started_at) { @builder_session.start!(facilitator: @facilitator) }
    travel_to(started_at + 6.hours) { @builder_session.synchronize! }
    sign_in_as(@facilitator)

    patch timing_builder_session_path(@builder_session), params: {
      started_at: "2026-08-24T18:00",
      ended_at: "2026-08-24T19:30"
    }

    assert_redirected_to builder_session_path(@builder_session)
    assert_equal started_at + 90.minutes, @builder_session.reload.ended_at

    delete sign_out_path
    sign_in_as(@builder)
    patch timing_builder_session_path(@builder_session), params: {
      started_at: "2026-08-24T18:00",
      ended_at: "2026-08-24T20:00"
    }

    assert_redirected_to builder_sessions_path
    assert_equal started_at + 90.minutes, @builder_session.reload.ended_at
  end

  private

  def sign_in_as(user)
    token = user.reload.generate_token_for(:email_verification)
    get verify_email_path(token: token)
    post verify_email_path, params: { token: token }
  end
end
