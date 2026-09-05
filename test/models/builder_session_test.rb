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

      assert_equal "builder_updates", @builder_session.state
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

  test "starting immediately distributes the full core budget across attending Builders" do
    second_builder = User.create!(email: "second@example.com", name: "Second Builder", enrollment_status: "active", verified_at: Time.current)
    third_builder = User.create!(email: "third@example.com", name: "Third Builder", enrollment_status: "active", verified_at: Time.current)
    [ @builder, second_builder, third_builder ].each { |builder| @builder_session.mark_present!(builder) }
    started_at = Time.zone.parse("2026-08-24 18:00")

    travel_to(started_at) { @builder_session.start!(facilitator: @facilitator, duration_seconds: 30.minutes.to_i) }

    assert_equal "builder_updates", @builder_session.state
    assert_equal started_at, @builder_session.builder_updates_started_at
    attending = @builder_session.attendances.where(role: "builder", status: "present")
    assert_equal [ "queued", "queued", "speaking" ], attending.order(:speaker_state).pluck(:speaker_state)
    assert_equal [ 10.minutes.to_i ], attending.pluck(:speaker_allotted_seconds).uniq
    assert_equal 30.minutes.to_i, attending.sum(:speaker_allotted_seconds)
  end

  test "starting randomizes the attending Builder order" do
    second_builder = User.create!(email: "second@example.com", name: "Second Builder", enrollment_status: "active", verified_at: Time.current)
    third_builder = User.create!(email: "third@example.com", name: "Third Builder", enrollment_status: "active", verified_at: Time.current)
    fourth_builder = User.create!(email: "fourth@example.com", name: "Fourth Builder", enrollment_status: "active", verified_at: Time.current)
    expected_builders = [ @builder, second_builder, third_builder, fourth_builder ]
    zero_random = Object.new.tap { |random| random.define_singleton_method(:rand) { |*| 0 } }

    @builder_session.start!(facilitator: @facilitator, duration_seconds: 40.minutes.to_i, random: zero_random)

    speaker_order = @builder_session.attendances.where(role: "builder").order(:speaker_position).pluck(:user_id)
    assert_equal expected_builders.rotate.map(&:id), speaker_order
    assert_equal [ 10.minutes.to_i ], @builder_session.attendances.where(role: "builder").pluck(:speaker_allotted_seconds).uniq
  end

  test "configured pre-core delays randomization and preserves the full core budget" do
    second_builder = User.create!(email: "second@example.com", name: "Second Builder", enrollment_status: "active", verified_at: Time.current)
    started_at = Time.zone.parse("2026-08-24 18:00")
    zero_random = Object.new.tap { |random| random.define_singleton_method(:rand) { |*| 0 } }

    travel_to started_at do
      @builder_session.start!(
        facilitator: @facilitator,
        duration_seconds: 20.minutes.to_i,
        pre_core_duration_seconds: 5.minutes.to_i,
        hangout_duration_seconds: 10.minutes.to_i,
        random: zero_random
      )
    end

    assert_equal "connection", @builder_session.state
    assert_equal 5.minutes.to_i, @builder_session.pre_core_duration_seconds
    assert_equal 10.minutes.to_i, @builder_session.hangout_duration_seconds
    assert_nil @builder_session.builder_updates_started_at
    assert_empty @builder_session.attendances.where(role: "builder").where.not(speaker_state: nil)

    travel_to(started_at + 5.minutes) { @builder_session.synchronize!(random: zero_random) }

    assert_equal "builder_updates", @builder_session.state
    assert_equal started_at + 5.minutes, @builder_session.builder_updates_started_at
    assert_equal [ second_builder.id, @builder.id ],
      @builder_session.attendances.where(role: "builder").order(:speaker_position).pluck(:user_id)
    assert_equal [ 10.minutes.to_i ],
      @builder_session.attendances.where(role: "builder").pluck(:speaker_allotted_seconds).uniq
    assert_equal 20.minutes.to_i, @builder_session.phase_remaining_seconds(at: started_at + 5.minutes)
  end

  test "configured hangout counts down through zero until the facilitator finishes" do
    started_at = Time.zone.parse("2026-08-24 18:00")
    travel_to started_at do
      @builder_session.start!(
        facilitator: @facilitator,
        duration_seconds: 20.minutes.to_i,
        hangout_duration_seconds: 2.minutes.to_i
      )
    end
    @builder_session.finish_current_speaker!(at: started_at + 10.seconds)

    assert_equal "hangout", @builder_session.state
    assert_equal "countdown", @builder_session.clock_mode
    assert_equal 90, @builder_session.clock_seconds(at: started_at + 40.seconds)
    assert_equal(-30, @builder_session.clock_seconds(at: started_at + 160.seconds))

    @builder_session.synchronize!(at: started_at + 160.seconds)

    assert_equal "hangout", @builder_session.state
    assert_nil @builder_session.ended_at
    @builder_session.finish!(at: started_at + 161.seconds)
    assert_equal "completed", @builder_session.state
  end

  test "starting freezes the current Active Builder roster and drops stale pre-session choices" do
    @builder_session.mark_present!(@builder)
    @builder.update!(enrollment_status: "withdrawn")
    replacement = User.create!(email: "replacement@example.com", name: "Replacement Builder", enrollment_status: "active", verified_at: Time.current)

    @builder_session.start!(facilitator: @facilitator, duration_seconds: 30.minutes.to_i)

    assert_not @builder_session.attendances.exists?(user: @builder)
    replacement_attendance = @builder_session.attendances.find_by!(user: replacement)
    assert_equal "present", replacement_attendance.status
    assert_includes %w[speaking queued], replacement_attendance.speaker_state
  end

  test "canceling a mistaken start discards its run data and restores the scheduled session" do
    scheduled_attributes = @builder_session.attributes.slice("scheduled_starts_at", "scheduled_ends_at", "title", "google_event_id")
    started_at = Time.zone.parse("2026-08-24 18:00")
    second_builder = User.create!(email: "second@example.com", name: "Second Builder", enrollment_status: "active", verified_at: Time.current)
    @builder_session.mark_absent!(@builder)
    travel_to(started_at) { @builder_session.start!(facilitator: @other_facilitator, duration_seconds: 30.minutes.to_i) }
    @builder_session.pause!(at: started_at + 1.minute)

    cancelled = @builder_session.cancel_start!(expected_started_at: started_at.iso8601(6))

    assert cancelled
    assert_equal "ready", @builder_session.state
    assert_equal scheduled_attributes, @builder_session.attributes.slice(*scheduled_attributes.keys)
    assert_equal @facilitator, @builder_session.assigned_facilitator
    assert_nil @builder_session.facilitator_name_snapshot
    assert_nil @builder_session.started_at
    assert_nil @builder_session.builder_updates_started_at
    assert_nil @builder_session.closing_started_at
    assert_nil @builder_session.hangout_started_at
    assert_nil @builder_session.ended_at
    assert_nil @builder_session.timer_duration_seconds
    assert_equal 0, @builder_session.pre_core_duration_seconds
    assert_equal 0, @builder_session.hangout_duration_seconds
    assert_nil @builder_session.finish_reason
    assert_equal [ [ "Builder", "absent" ], [ "Second Builder", "present" ] ],
      @builder_session.attendances.order(:display_name).pluck(:display_name, :status)
    @builder_session.attendances.each do |attendance|
      assert_nil attendance.arrived_at
      assert_nil attendance.speaker_state
      assert_nil attendance.speaker_position
      assert_nil attendance.speaker_allotted_seconds
      assert_nil attendance.speaker_started_at
      assert_nil attendance.speaker_ended_at
      assert_equal 0, attendance.speaker_paused_seconds
    end
    assert_empty @builder_session.pauses
  end

  test "a delayed cancellation cannot discard a newer timer run" do
    first_start = Time.zone.parse("2026-08-24 18:00")
    travel_to(first_start) { @builder_session.start!(facilitator: @facilitator) }
    first_token = @builder_session.started_at.iso8601(6)
    assert @builder_session.cancel_start!(expected_started_at: first_token)

    travel_to(first_start + 1.minute) { @builder_session.start!(facilitator: @facilitator) }

    assert_not @builder_session.cancel_start!(expected_started_at: first_token)
    assert_equal "builder_updates", @builder_session.state
    assert_equal first_start + 1.minute, @builder_session.started_at
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

  test "the final speaker finishes the core and starts the hangout timer" do
    started_at = Time.zone.parse("2026-08-24 18:00")

    travel_to started_at do
      @builder_session.start!(facilitator: @facilitator, duration_seconds: 30.minutes.to_i)
    end

    travel_to started_at + 5.minutes do
      @builder_session.synchronize!

      attendance = @builder_session.attendances.find_by!(user: @builder)
      assert_equal "builder_updates", @builder_session.state
      assert_equal "speaking", attendance.speaker_state
      assert_equal 1, attendance.speaker_position
      assert_equal 30.minutes.to_i, attendance.speaker_allotted_seconds
      assert_equal 25.minutes.to_i, @builder_session.clock_seconds
    end

    travel_to started_at + 10.minutes do
      @builder_session.finish_current_speaker!

      assert_equal "hangout", @builder_session.state
      assert_equal Time.current, @builder_session.hangout_started_at
      assert_equal "completed", @builder_session.attendances.find_by!(user: @builder).speaker_state
    end

    travel_to started_at + 11.minutes do
      @builder_session.synchronize!

      assert_equal "hangout", @builder_session.state
      assert_equal 1.minute.to_i, @builder_session.clock_seconds
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

  test "finishing early redistributes all remaining core time before the deadline starts hangout" do
    second_builder = User.create!(email: "second@example.com", name: "Second Builder", enrollment_status: "active", verified_at: Time.current)
    third_builder = User.create!(email: "third@example.com", name: "Third Builder", enrollment_status: "active", verified_at: Time.current)
    started_at = Time.zone.parse("2026-08-24 18:00")

    travel_to started_at do
      @builder_session.start!(facilitator: @facilitator, duration_seconds: 30.minutes.to_i)
    end
    travel_to started_at + 5.minutes do
      @builder_session.synchronize!
      assert_equal 5.minutes.to_i, @builder_session.clock_seconds
    end
    travel_to started_at + 15.minutes do
      @builder_session.finish_current_speaker!
      assert_equal 7.minutes.to_i + 30, @builder_session.current_speaker_attendance.speaker_allotted_seconds
      assert_equal 15.minutes.to_i, @builder_session.phase_remaining_seconds
    end
    travel_to started_at + 30.minutes do
      @builder_session.synchronize!
      assert_equal "hangout", @builder_session.state
      assert_equal started_at + 30.minutes, @builder_session.hangout_started_at
    end
  end

  test "an overdrawn speaker runs negative and every Next redistributes the remaining core budget" do
    User.create!(email: "second@example.com", name: "Second Builder", enrollment_status: "active", verified_at: Time.current)
    User.create!(email: "third@example.com", name: "Third Builder", enrollment_status: "active", verified_at: Time.current)
    started_at = Time.zone.parse("2026-08-24 18:00")

    travel_to(started_at) { @builder_session.start!(facilitator: @facilitator, duration_seconds: 30.minutes.to_i) }

    travel_to started_at + 12.minutes do
      expected_next = @builder_session.unspoken_speakers.first
      assert_equal(-2.minutes.to_i, @builder_session.clock_seconds)

      @builder_session.finish_current_speaker!

      assert_equal expected_next, @builder_session.current_speaker_attendance
      assert_equal 9.minutes.to_i, @builder_session.clock_seconds
      assert_equal [ 9.minutes.to_i ], @builder_session.unspoken_speakers.pluck(:speaker_allotted_seconds).uniq
    end

    travel_to started_at + 17.minutes do
      expected_next = @builder_session.unspoken_speakers.first
      assert_equal 4.minutes.to_i, @builder_session.clock_seconds

      @builder_session.finish_current_speaker!

      assert_equal expected_next, @builder_session.current_speaker_attendance
      assert_equal 13.minutes.to_i, @builder_session.clock_seconds
    end
  end

  test "attendance changes redistribute the remaining core budget without double-counting elapsed time" do
    second_builder = User.create!(email: "second@example.com", name: "Second Builder", enrollment_status: "active", verified_at: Time.current)
    third_builder = User.create!(email: "third@example.com", name: "Third Builder", enrollment_status: "active", verified_at: Time.current)
    started_at = Time.zone.parse("2026-08-24 18:00")
    travel_to(started_at) { @builder_session.start!(facilitator: @facilitator, duration_seconds: 30.minutes.to_i) }
    absent_builder = @builder_session.unspoken_speakers.first.user

    travel_to started_at + 3.minutes do
      @builder_session.mark_absent!(absent_builder)

      assert_equal 13.minutes.to_i + 30, @builder_session.clock_seconds
      assert_equal [ 13.minutes.to_i + 30 ], @builder_session.unspoken_speakers.pluck(:speaker_allotted_seconds).uniq

      @builder_session.mark_present!(absent_builder)

      assert_equal 9.minutes.to_i, @builder_session.clock_seconds
      assert_equal [ 9.minutes.to_i ], @builder_session.unspoken_speakers.pluck(:speaker_allotted_seconds).uniq
    end
  end

  test "a queued Builder marked present during core returns at a random queue position" do
    User.create!(email: "second@example.com", name: "Second Builder", enrollment_status: "active", verified_at: Time.current)
    User.create!(email: "third@example.com", name: "Third Builder", enrollment_status: "active", verified_at: Time.current)
    User.create!(email: "fourth@example.com", name: "Fourth Builder", enrollment_status: "active", verified_at: Time.current)
    @builder_session.start!(facilitator: @facilitator)
    queued = @builder_session.unspoken_speakers.last
    remaining_order = @builder_session.unspoken_speakers.where.not(id: queued.id).to_a
    middle_random = Object.new.tap { |random| random.define_singleton_method(:rand) { |*| 1 } }

    @builder_session.mark_absent!(queued.user)
    assert_nil queued.reload.speaker_state
    assert_nil queued.speaker_position

    @builder_session.mark_present!(queued.user, random: middle_random)
    assert_equal "queued", queued.reload.speaker_state
    assert_equal [ remaining_order.first, queued, remaining_order.second ], @builder_session.unspoken_speakers.to_a
    assert_equal [ 7.minutes.to_i + 30 ], @builder_session.unspoken_speakers.pluck(:speaker_allotted_seconds).uniq
  end

  test "an absent current speaker can rejoin the active core at a new position" do
    @builder_session.start!(facilitator: @facilitator, duration_seconds: 30.minutes.to_i)
    attendance = @builder_session.current_speaker_attendance

    @builder_session.mark_absent!(attendance.user)

    assert_equal "builder_updates", @builder_session.state
    assert_nil @builder_session.current_speaker_attendance
    assert_equal "skipped", attendance.reload.speaker_state

    @builder_session.mark_present!(attendance.user)

    assert_equal "speaking", attendance.reload.speaker_state
    assert_equal attendance, @builder_session.current_speaker_attendance
  end

  test "a core with every expected Builder absent waits for live attendance" do
    @builder_session.mark_absent!(@builder)

    @builder_session.start!(facilitator: @facilitator, duration_seconds: 30.minutes.to_i)

    assert_equal "builder_updates", @builder_session.state
    assert_nil @builder_session.current_speaker_attendance

    @builder_session.mark_present!(@builder)

    assert_equal "speaking", @builder_session.current_speaker_attendance.speaker_state
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
      assert_equal 28.minutes.to_i, @builder_session.phase_remaining_seconds
    end
    travel_to started_at + 12.minutes do
      @builder_session.synchronize!
      assert_equal "builder_updates", @builder_session.state
      assert_equal 28.minutes.to_i, @builder_session.phase_remaining_seconds
      version = @builder_session.updated_at
      @builder_session.resume!
      assert_operator @builder_session.updated_at, :>, version
    end
    travel_to started_at + 39.minutes do
      @builder_session.synchronize!
      assert_equal "builder_updates", @builder_session.state
    end
    travel_to started_at + 40.minutes do
      @builder_session.synchronize!
      assert_equal "hangout", @builder_session.state
    end
    travel_to started_at + 6.hours do
      @builder_session.synchronize!
      assert_equal "completed", @builder_session.state
      assert_equal "automatic", @builder_session.finish_reason
      assert_equal started_at + 5.hours, @builder_session.ended_at
    end
  end

  test "a completed session accepts valid time corrections and rejects invalid boundaries" do
    started_at = Time.zone.parse("2026-08-24 18:00")
    travel_to(started_at) { @builder_session.start!(facilitator: @facilitator) }
    travel_to(started_at + 6.hours) { @builder_session.synchronize! }

    @builder_session.correct_times!(started_at: started_at - 5.minutes, ended_at: started_at + 90.minutes)

    assert_equal started_at - 5.minutes, @builder_session.started_at
    assert_equal started_at + 90.minutes, @builder_session.ended_at
    assert_equal "automatic", @builder_session.finish_reason
    assert_raises(ActiveRecord::RecordInvalid) do
      @builder_session.correct_times!(started_at:, ended_at: started_at - 1.minute)
    end
    assert_raises(ActiveRecord::RecordInvalid) do
      @builder_session.correct_times!(started_at: started_at + 1.minute, ended_at: started_at + 90.minutes)
    end
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
