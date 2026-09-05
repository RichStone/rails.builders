require "application_system_test_case"

class BuilderSessionsSystemTest < ApplicationSystemTestCase
  setup do
    @facilitator = User.create!(
      email: "facilitator@example.com",
      name: "Session Facilitator",
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
    @program = Program.create!(
      name: "Continuous",
      starts_on: Date.current,
      ends_on: 4.months.from_now.to_date,
      capacity: 9,
      main_facilitator: @facilitator
    )
    @builder_session = @program.builder_sessions.create!(
      assigned_facilitator: @facilitator,
      google_event_id: "browser-session",
      title: "Browser session",
      meet_url: "https://meet.google.com/abc-defg-hij",
      scheduled_starts_at: 10.minutes.from_now,
      scheduled_ends_at: 40.minutes.from_now,
      time_zone: "Europe/Madrid"
    )
  end

  test "public schedule becomes a shared live room with role-specific controls" do
    visit root_path
    assert_text "Browser session"
    assert_no_text "abc-defg-hij"

    sign_in_as(@builder)
    click_link "Sessions"
    click_link "Browser session"
    assert_link "Join Google Meet"
    assert_no_button "Start session"
    assert_text "Active Builder"
    assert_text "Attending"

    click_link "Sign out"
    sign_in_as(@facilitator)
    click_link "Sessions"
    click_link "Browser session"
    within(".attendance-row", text: "Active Builder") do
      click_button "Mark not attending"
      assert_button "Confirm attendance"
      click_button "Confirm attendance"
      assert_button "Mark not attending"
    end
    configure_session(core: 30)
    click_button "Start session"

    assert_selector ".live-phase", text: /Core session/i
    assert_text "Active Builder"
    assert_button "Pause"
    assert_button "Next"

    click_button "Pause"
    assert_button "Resume"
    click_button "Resume", exact: true
    assert_button "Pause"
    click_button "Next"
    assert_selector ".live-phase", text: /Hangout/i
    find("summary", text: "Finish session").click
    click_button "Confirm finish session"
    assert_text(/session complete/i)
    assert_text "Processing transcript"
  end

  test "facilitator edits analysis and expands the private session artifacts" do
    started_at = 2.hours.ago
    @builder_session.update!(
      state: "completed",
      started_at:,
      hangout_started_at: started_at + 30.minutes,
      ended_at: started_at + 45.minutes,
      facilitator_name_snapshot: @facilitator.name
    )
    @builder_session.create_transcript!(
      state: "ready",
      source: "manual",
      content: "Ada: We shipped the smaller onboarding flow.",
      summary_notes: "## Flow summary\n\n- Ship the narrow path first.",
      session_analysis: "## Ada\n\n**Current project:** Onboarding"
    )
    sign_in_as(@facilitator)

    visit builder_session_path(@builder_session)
    assert_selector "[data-session-analysis-content] h2", text: "Ada"
    assert_no_selector "details[data-session-notes][open]"
    assert_no_selector "details[data-session-transcript][open]"

    find("details[data-session-notes] > summary").click
    assert_selector "details[data-session-notes][open]", text: /Ship the narrow path first/
    find("details[data-session-transcript] > summary").click
    assert_selector "details[data-session-transcript][open]", text: /smaller onboarding flow/

    find(".session-context-editor > summary").click
    fill_in "Session analysis (Markdown)", with: "## Ada\n\n**Current project:** Loop Labs\n\n**Latest trend:** She narrowed the launch again."
    click_button "Save session analysis"

    assert_selector "[data-session-analysis-content] h2", text: "Ada"
    assert_selector "[data-session-analysis-content] strong", text: "Current project:"
    assert_text "She narrowed the launch again."
  end

  test "finishing the core starts a count-up hangout before the session can finish" do
    sign_in_as(@facilitator)
    click_link "Sessions"
    click_link "Browser session"
    configure_session(core: 1)
    click_button "Start session"

    assert_selector ".live-phase", text: /Core session/i
    assert_button "Next"
    assert_no_selector "summary", text: "Finish session"
    click_button "Finish core & start hangout"

    assert_selector ".live-phase", text: /Hangout/i
    assert_selector "summary", text: "Finish session"
    assert_no_selector ".attendance-row", text: /Speaking/
    assert_selector ".session-clock", text: "0:01", wait: 3
  end

  test "timer controls survive repeated attendance, pause, queue, phase, and correction changes" do
    %w[Second Third Fourth].each do |name|
      User.create!(email: "#{name.downcase}@example.com", name: "#{name} Builder", enrollment_status: "active", verified_at: Time.current)
    end
    sign_in_as(@facilitator)
    click_link "Sessions"
    click_link "Browser session"

    2.times do
      within(".attendance-row", text: "Second Builder") do
        click_button "Mark not attending"
        assert_button "Confirm attendance"
        click_button "Confirm attendance"
        assert_button "Mark not attending"
      end
    end

    configure_session(core: 5)
    click_button "Start session"
    assert_selector ".live-phase", text: /Core session/i
    assert_selector ".speaker-queue .attendance-row", count: 3
    assert_selector ".speaker-queue .attendance-row", text: /1:15 allocated/, count: 3

    2.times do
      click_button "Pause"
      assert_button "Resume"
      frozen_clock = find(".session-clock").text
      sleep 0.4
      assert_equal frozen_clock, find(".session-clock").text
      click_button "Resume", exact: true
      assert_button "Pause"
    end

    2.times do
      queue_item = all("[data-speaker-order-target='item']", count: 3)[1]
      queued_name = queue_item.find("strong").text
      queue_item.find("button[data-action='speaker-order#earlier']").click
      assert_selector "[data-speaker-order-target='status']", text: "Speaker order saved.", visible: :all
      find("[data-speaker-order-target='item']", text: queued_name)
        .find("button[data-action='speaker-order#later']").click
      assert_selector "[data-speaker-order-target='status']", text: "Speaker order saved.", visible: :all
    end

    2.times do
      original_order = queued_builder_names
      expected_order = [ original_order.second, original_order.first, *original_order.drop(2) ]

      drag_queued_builder_before(original_order.second, original_order.first)

      assert_selector "[data-speaker-order-target='status']", text: "Speaker order saved.", visible: :all
      assert_equal expected_order, queued_builder_names
      visit current_path
      assert_equal expected_order, queued_builder_names
    end

    2.times do
      within(all(".attendance-panel", minimum: 2).last) do
        within(".attendance-row", text: "Second Builder") { click_button "Mark absent" }
      end
      assert_selector ".speaker-queue .attendance-row", count: 2
      within(all(".attendance-panel", minimum: 2).last) do
        within(".attendance-row", text: "Second Builder") { click_button "Mark present" }
      end
      assert_selector ".speaker-queue .attendance-row", count: 3
    end

    2.times do
      previous_speaker = find(".live-session-stage h2").text
      click_button "Next"
      assert_no_selector ".live-session-stage h2", text: previous_speaker
    end

    find("summary", text: "Finish core & start hangout").click
    assert_button "Confirm finish core"
    find("summary", text: "Finish core & start hangout").click
    assert_no_button "Confirm finish core"
    assert_selector ".live-phase", text: /Core session/i
    find("summary", text: "Finish core & start hangout").click
    click_button "Confirm finish core"
    assert_selector ".live-phase", text: /Hangout/i

    2.times do
      click_button "Pause"
      assert_button "Resume"
      click_button "Resume", exact: true
      assert_button "Pause"
    end
    assert_selector ".session-clock", text: "0:01", wait: 3

    find("summary", text: "Finish session").click
    assert_button "Confirm finish session"
    find("summary", text: "Finish session").click
    assert_no_button "Confirm finish session"
    find("summary", text: "Finish session").click
    click_button "Confirm finish session"
    assert_text(/session complete/i)

    zone = ActiveSupport::TimeZone["Europe/Madrid"]
    2.times do |index|
      corrected_start = (Time.current - (index + 3).minutes).in_time_zone(zone).strftime("%Y-%m-%dT%H:%M")
      corrected_end = (Time.current + (index + 3).minutes).in_time_zone(zone).strftime("%Y-%m-%dT%H:%M")
      set_datetime_local "Actual start time", corrected_start
      set_datetime_local "Actual end time", corrected_end
      click_button "Correct session times"
      assert_text "Session times corrected."
      assert_equal zone.parse(corrected_start), @builder_session.reload.started_at
    end

    2.times do
      within(".attendance-row", text: "Second Builder") do
        click_button "Mark absent"
        assert_button "Mark present"
        click_button "Mark present"
        assert_button "Mark absent"
      end
    end
  end

  test "an overdrawn speaker stays negative and Next redistributes on every click" do
    %w[Second Third].each do |name|
      User.create!(email: "#{name.downcase}@example.com", name: "#{name} Builder", enrollment_status: "active", verified_at: Time.current)
    end
    sign_in_as(@facilitator)
    click_link "Sessions"
    click_link "Browser session"
    configure_session(core: 5)
    click_button "Start session"
    assert_selector ".live-phase", text: /Core session/i

    first_speaker = @builder_session.reload.current_speaker_attendance
    first_budget = first_speaker.speaker_allotted_seconds
    first_speaker.update!(speaker_started_at: Time.current - first_budget.seconds - 10.seconds)
    @builder_session.touch
    visit builder_session_path(@builder_session)
    assert_selector ".session-clock", text: /−0:1\d/

    previous_budget = first_budget
    2.times do
      previous_name = @builder_session.reload.current_speaker_attendance.display_name
      expected_next = @builder_session.unspoken_speakers.first

      click_button "Next"

      assert_no_selector ".live-session-stage h2", text: previous_name
      assert_selector ".live-session-stage h2", text: expected_next.display_name
      next_speaker = @builder_session.reload.current_speaker_attendance
      assert_operator next_speaker.speaker_allotted_seconds, :>, previous_budget
      previous_budget = next_speaker.speaker_allotted_seconds
    end
  end

  test "an outside-window session can start and discard its timer run repeatedly" do
    second_builder = User.create!(
      email: "second@example.com",
      name: "Second Builder",
      enrollment_status: "active",
      verified_at: Time.current
    )
    @builder_session.update!(
      scheduled_starts_at: 2.hours.from_now,
      scheduled_ends_at: 3.hours.from_now
    )
    sign_in_as(@facilitator)
    click_link "Sessions"
    click_link "Browser session"

    assert_text "outside the scheduled start window"
    within(".attendance-row", text: "Active Builder") { click_button "Mark not attending" }

    2.times do |index|
      configure_session(pre_core: 1, core: 2, hangout: 1)
      click_button "Start session"

      assert_selector ".live-phase", text: /Pre-core/i
      assert_no_selector ".attendance-row", text: /Speaking/
      if index.zero?
        click_button "Start core session"
        assert_selector ".live-phase", text: /Core session/i
        assert_selector ".live-session-stage h2", text: second_builder.name
      end

      find("summary", text: "Cancel session").click
      click_button "Discard session run"

      assert_text "Mistaken session start discarded."
      assert_selector ".session-detail-heading .eyebrow", text: /Ready/i
      within(".attendance-row", text: "Active Builder") { assert_button "Confirm attendance" }
    end
  end

  test "a configured hangout counts below zero until it is explicitly finished" do
    sign_in_as(@facilitator)
    click_link "Sessions"
    click_link "Browser session"
    configure_session(core: 1, hangout: 1)
    click_button "Start session"
    click_button "Finish core & start hangout"

    assert_selector ".live-phase", text: /Hangout/i
    assert_selector ".session-clock", text: /0:5\d/

    @builder_session.reload.update!(hangout_started_at: 70.seconds.ago)
    visit builder_session_path(@builder_session)
    assert_selector ".session-clock", text: /−0:1\d/
    find("summary", text: "Finish session").click
    click_button "Confirm finish session"
    assert_text(/session complete/i)
  end

  private

  def configure_session(pre_core: 0, core:, hangout: 0)
    fill_in "Pre-core (minutes)", with: pre_core
    fill_in "Core (minutes)", with: core
    fill_in "Hangout (minutes, 0 counts up)", with: hangout
  end

  def sign_in_as(user)
    visit verify_email_path(token: user.reload.generate_token_for(:email_verification))
    assert_current_path dashboard_path
  end

  def set_datetime_local(label, value)
    page.execute_script("arguments[0].value = arguments[1]", find_field(label), value)
  end

  def queued_builder_names
    all("[data-speaker-order-target='item'] strong").map(&:text)
  end

  def drag_queued_builder_before(source_name, target_name)
    source = find("[data-speaker-order-target='item']", text: source_name)
    target = find("[data-speaker-order-target='item']", text: target_name)
    source.drag_to(target, html5: true)
  end
end
