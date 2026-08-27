require "test_helper"

class BuilderSessionTest < ActiveSupport::TestCase
  setup do
    @facilitator = User.create!(
      email: "facilitator@example.com",
      name: "Facilitator",
      facilitator: true,
      enrollment_status: "active",
      verified_at: Time.current
    )
    @builder = User.create!(
      email: "builder@example.com",
      name: "Builder",
      enrollment_status: "active",
      verified_at: Time.current
    )
    User.create!(
      email: "inactive@example.com",
      name: "Inactive Builder",
      enrollment_status: "withdrawn",
      verified_at: Time.current
    )
    @other_facilitator = User.create!(
      email: "other-facilitator@example.com",
      name: "Other Facilitator",
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
    @builder_session = @program.builder_sessions.create!(
      assigned_facilitator: @facilitator,
      google_event_id: "calendar-event-1",
      title: "Build together",
      scheduled_starts_at: Time.zone.parse("2026-08-24 18:00"),
      scheduled_ends_at: Time.zone.parse("2026-08-24 19:00"),
      time_zone: "Europe/Madrid"
    )
  end

  test "starting snapshots the timer, facilitator, and expected attendees" do
    travel_to Time.zone.parse("2026-08-24 18:02") do
      @builder_session.start!(facilitator: @facilitator, duration_seconds: 2_700)

      assert_equal "connection", @builder_session.state
      assert_equal Time.current, @builder_session.started_at
      assert_equal 2_700, @builder_session.timer_duration_seconds
      assert_equal "Facilitator", @builder_session.facilitator_name_snapshot
      assert_equal [ "Builder", "Facilitator" ], @builder_session.attendances.order(:display_name).pluck(:display_name)
      assert_not @builder_session.attendances.exists?(user: @other_facilitator)
      assert_equal "builder", @builder_session.attendances.find_by!(user: @builder).role
      facilitator_attendance = @builder_session.attendances.find_by!(user: @facilitator)
      assert_equal "facilitator", facilitator_attendance.role
      assert_equal "present", facilitator_attendance.status
      assert_equal Time.current, facilitator_attendance.arrived_at
    end
  end

  test "the default core timer excludes the optional 30-minute hangout" do
    assert_equal 30, @builder_session.default_timer_minutes

    @builder_session.update!(scheduled_ends_at: @builder_session.scheduled_starts_at + 90.minutes)
    assert_equal 60, @builder_session.default_timer_minutes

    @builder_session.start!(facilitator: @facilitator)

    assert_equal 60.minutes.to_i, @builder_session.timer_duration_seconds
  end

  test "a program cannot have two active sessions" do
    @builder_session.start!(facilitator: @facilitator)
    second = @program.builder_sessions.create!(
      assigned_facilitator: @facilitator,
      google_event_id: "calendar-event-2",
      title: "Another session",
      scheduled_starts_at: 1.week.from_now,
      scheduled_ends_at: 1.week.from_now + 1.hour,
      time_zone: "Europe/Madrid"
    )

    assert_raises(BuilderSession::AlreadyActive) { second.start!(facilitator: @facilitator) }
    assert_equal "ready", second.reload.state
  end

  test "meeting links must be canonical Google Meet URLs" do
    @builder_session.meet_url = "javascript:alert(1)"
    assert_not @builder_session.valid?

    @builder_session.meet_url = "https://meet.google.com.evil.test/abc-defg-hij"
    assert_not @builder_session.valid?

    @builder_session.meet_url = "https://meet.google.com/abc-defg-hij"
    assert @builder_session.valid?
    assert_equal "abc-defg-hij", @builder_session.meeting_code
  end

  test "present builders share the update pool and finishing early begins closing then hangout" do
    started_at = Time.zone.parse("2026-08-24 18:00")

    travel_to started_at do
      @builder_session.start!(facilitator: @facilitator, duration_seconds: 30.minutes.to_i)
      @builder_session.mark_present!(@builder)
    end

    travel_to started_at + 5.minutes do
      @builder_session.synchronize!

      attendance = @builder_session.attendances.find_by!(user: @builder)
      assert_equal "builder_updates", @builder_session.state
      assert_equal "speaking", attendance.speaker_state
      assert_equal 1, attendance.speaker_position
      assert_equal 24.minutes.to_i, attendance.speaker_allotted_seconds
    end

    travel_to started_at + 10.minutes do
      @builder_session.finish_current_speaker!

      assert_equal "closing", @builder_session.state
      assert_equal Time.current, @builder_session.closing_started_at
      assert_equal "completed", @builder_session.attendances.find_by!(user: @builder).speaker_state
    end

    travel_to started_at + 11.minutes do
      @builder_session.synchronize!

      assert_equal "hangout", @builder_session.state
      assert_equal Time.current, @builder_session.hangout_started_at
    end
  end

  test "reordering unspoken speakers preserves the current speaker position" do
    second_builder = User.create!(
      email: "second@example.com",
      name: "Second Builder",
      enrollment_status: "active",
      verified_at: Time.current
    )
    third_builder = User.create!(
      email: "third@example.com",
      name: "Third Builder",
      enrollment_status: "active",
      verified_at: Time.current
    )
    fourth_builder = User.create!(
      email: "fourth@example.com",
      name: "Fourth Builder",
      enrollment_status: "active",
      verified_at: Time.current
    )

    @builder_session.start!(facilitator: @facilitator)
    [ @builder, second_builder, third_builder, fourth_builder ].each { |builder| @builder_session.mark_present!(builder) }
    @builder_session.advance_phase!
    @builder_session.finish_current_speaker!

    completed_speaker = @builder_session.attendances.find_by!(speaker_state: "completed")
    current_speaker = @builder_session.current_speaker_attendance
    completed_position = completed_speaker.speaker_position
    current_position = current_speaker.speaker_position
    requested_order = @builder_session.unspoken_speakers.pluck(:id).reverse

    @builder_session.reorder_unspoken_speakers!(requested_order)

    assert_equal requested_order, @builder_session.unspoken_speakers.pluck(:id)
    assert_equal completed_position, completed_speaker.reload.speaker_position
    assert_equal "completed", completed_speaker.speaker_state
    assert_equal current_position, current_speaker.reload.speaker_position
    assert_equal "speaking", current_speaker.speaker_state
  end

  test "speaker positions are unique within a session" do
    second_builder = User.create!(
      email: "second@example.com",
      name: "Second Builder",
      enrollment_status: "active",
      verified_at: Time.current
    )

    @builder_session.start!(facilitator: @facilitator)
    [ @builder, second_builder ].each { |builder| @builder_session.mark_present!(builder) }
    @builder_session.advance_phase!

    current_speaker = @builder_session.current_speaker_attendance
    queued_speaker = @builder_session.unspoken_speakers.first
    queued_speaker.speaker_position = current_speaker.speaker_position

    assert_not queued_speaker.valid?
    assert queued_speaker.errors.of_kind?(:speaker_position, :taken)
  end

  test "reordering rejects incomplete duplicate and cross-session speaker sets" do
    second_builder = User.create!(email: "second@example.com", name: "Second Builder", enrollment_status: "active", verified_at: Time.current)
    third_builder = User.create!(email: "third@example.com", name: "Third Builder", enrollment_status: "active", verified_at: Time.current)
    @builder_session.start!(facilitator: @facilitator)
    [ @builder, second_builder, third_builder ].each { |builder| @builder_session.mark_present!(builder) }
    @builder_session.advance_phase!
    original_order = @builder_session.unspoken_speakers.pluck(:id)

    other_session = @program.builder_sessions.create!(
      google_event_id: "calendar-event-2",
      title: "Another session",
      scheduled_starts_at: 1.week.from_now,
      scheduled_ends_at: 1.week.from_now + 1.hour,
      time_zone: "Europe/Madrid"
    )
    other_attendance = other_session.attendances.create!(
      user: @builder,
      display_name: "Builder",
      role: "builder",
      status: "present",
      speaker_state: "queued",
      speaker_position: 1
    )
    invalid_orders = [
      original_order.drop(1),
      [ original_order.first, original_order.first ],
      [ original_order.first, other_attendance.id ],
      [ original_order.first, @builder_session.current_speaker_attendance.id ]
    ]

    invalid_orders.each do |invalid_order|
      assert_raises(BuilderSession::InvalidSpeakerOrder) do
        @builder_session.reorder_unspoken_speakers!(invalid_order)
      end
    end
    assert_equal original_order, @builder_session.unspoken_speakers.pluck(:id)
  end

  test "speaker overtime is redistributed while the closing minute stays reserved" do
    second_builder = User.create!(email: "second@example.com", name: "Second Builder", enrollment_status: "active", verified_at: Time.current)
    third_builder = User.create!(email: "third@example.com", name: "Third Builder", enrollment_status: "active", verified_at: Time.current)
    started_at = Time.zone.parse("2026-08-24 18:00")

    travel_to started_at do
      @builder_session.start!(facilitator: @facilitator, duration_seconds: 30.minutes.to_i)
      [ @builder, second_builder, third_builder ].each { |builder| @builder_session.mark_present!(builder) }
    end
    travel_to started_at + 5.minutes do
      @builder_session.synchronize!
      assert_equal 8.minutes.to_i, @builder_session.current_speaker_attendance.speaker_allotted_seconds
    end
    travel_to started_at + 15.minutes do
      @builder_session.finish_current_speaker!
      assert_equal 7.minutes.to_i, @builder_session.current_speaker_attendance.speaker_allotted_seconds
      assert_equal 14.minutes.to_i, @builder_session.phase_remaining_seconds
    end
    travel_to started_at + 29.minutes do
      @builder_session.synchronize!
      assert_equal "closing", @builder_session.state
    end
  end

  test "a queued Builder marked absent can arrive later at the end of the queue" do
    second_builder = User.create!(email: "second@example.com", name: "Second Builder", enrollment_status: "active", verified_at: Time.current)
    @builder_session.start!(facilitator: @facilitator)
    [ @builder, second_builder ].each { |builder| @builder_session.mark_present!(builder) }
    @builder_session.advance_phase!
    queued = @builder_session.unspoken_speakers.first

    @builder_session.mark_absent!(queued.user)
    assert_nil queued.reload.speaker_state
    assert_nil queued.speaker_position

    @builder_session.mark_present!(queued.user)
    assert_equal "queued", queued.reload.speaker_state
    assert_equal @builder_session.attendances.maximum(:speaker_position), queued.speaker_position
  end

  test "pausing freezes phase time and a forgotten session auto-finishes five hours after start" do
    started_at = Time.zone.parse("2026-08-24 18:00")

    travel_to started_at do
      @builder_session.start!(facilitator: @facilitator, duration_seconds: 30.minutes.to_i)
      @builder_session.mark_present!(@builder)
    end
    travel_to started_at + 2.minutes do
      version = @builder_session.updated_at
      @builder_session.pause!
      assert @builder_session.paused?
      assert_operator @builder_session.updated_at, :>, version
      assert_equal 3.minutes.to_i, @builder_session.phase_remaining_seconds
    end
    travel_to started_at + 12.minutes do
      @builder_session.synchronize!
      assert_equal "connection", @builder_session.state
      assert_equal 3.minutes.to_i, @builder_session.phase_remaining_seconds
      version = @builder_session.updated_at
      @builder_session.resume!
      assert_operator @builder_session.updated_at, :>, version
    end
    travel_to started_at + 15.minutes do
      @builder_session.synchronize!
      assert_equal "builder_updates", @builder_session.state
    end
    travel_to started_at + 6.hours do
      @builder_session.synchronize!
      assert_equal "completed", @builder_session.state
      assert_equal "automatic", @builder_session.finish_reason
      assert_equal started_at + 5.hours, @builder_session.ended_at
    end
  end

  test "an automatically closed session can record its actual earlier end" do
    started_at = Time.zone.parse("2026-08-24 18:00")
    travel_to(started_at) { @builder_session.start!(facilitator: @facilitator) }
    travel_to(started_at + 6.hours) { @builder_session.synchronize! }

    @builder_session.correct_automatic_end!(started_at + 90.minutes)

    assert_equal started_at + 90.minutes, @builder_session.ended_at
    assert_equal "automatic", @builder_session.finish_reason
    assert_raises(ActiveRecord::RecordInvalid) { @builder_session.correct_automatic_end!(started_at - 1.minute) }
  end

  test "a completed attendance correction does not invent an arrival time" do
    started_at = Time.zone.parse("2026-08-24 18:00")
    travel_to(started_at) { @builder_session.start!(facilitator: @facilitator) }
    travel_to(started_at + 1.hour) { @builder_session.finish! }

    travel_to(started_at + 1.day) { @builder_session.mark_present!(@builder) }

    attendance = @builder_session.attendances.find_by!(user: @builder)
    assert_equal "present", attendance.status
    assert_nil attendance.arrived_at
  end

  test "account deletion anonymizes attendance without erasing session history" do
    @builder_session.start!(facilitator: @facilitator)
    @builder_session.mark_present!(@builder)
    attendance = @builder_session.attendances.find_by!(user: @builder)

    assert @builder.delete_account!

    assert_nil attendance.reload.user_id
    assert_equal "Former Builder", attendance.display_name
    assert_equal "present", attendance.status
    assert BuilderSession.exists?(@builder_session.id)
  end

  test "facilitator account deletion anonymizes the session snapshot" do
    @builder_session.start!(facilitator: @other_facilitator)

    assert @other_facilitator.delete_account!

    assert_nil @builder_session.reload.assigned_facilitator_id
    assert_equal "Former Facilitator", @builder_session.facilitator_name_snapshot
    attendance = @builder_session.attendances.find_by!(role: "facilitator")
    assert_nil attendance.user_id
    assert_equal "Former Builder", attendance.display_name
  end

  test "the Program main facilitator cannot lose the role or delete their account before handoff" do
    @facilitator.facilitator = false

    assert_not @facilitator.save
    assert_includes @facilitator.errors[:facilitator], "cannot be removed while this person is a Program's main facilitator"
    @facilitator.reload
    assert_not @facilitator.delete_account!
    assert User.exists?(@facilitator.id)
  end
end
