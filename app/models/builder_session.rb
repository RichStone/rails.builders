class BuilderSession < ApplicationRecord
  AlreadyActive = Class.new(StandardError)
  InvalidSpeakerOrder = Class.new(StandardError)

  STATES = %w[ready cancelled connection builder_updates closing hangout completed].freeze
  ACTIVE_STATES = %w[connection builder_updates closing hangout].freeze

  belongs_to :program
  belongs_to :assigned_facilitator, class_name: "User", optional: true
  has_many :attendances, class_name: "BuilderSessionAttendance", dependent: :restrict_with_error
  has_many :pauses, class_name: "BuilderSessionPause", dependent: :restrict_with_error
  has_one :transcript, class_name: "BuilderSessionTranscript", dependent: :restrict_with_error

  encrypts :meet_url

  validates :google_event_id, :title, :time_zone, :scheduled_starts_at, :scheduled_ends_at, presence: true
  validates :google_event_id, uniqueness: { scope: :program_id }
  validates :google_event_id, length: { maximum: 1_024 }
  validates :title, length: { maximum: 200 }
  validates :description, length: { maximum: 20_000 }, allow_nil: true
  validates :location, :meet_url, length: { maximum: 500 }, allow_nil: true
  validates :time_zone, length: { maximum: 100 }
  validates :facilitator_name_snapshot, length: { maximum: 100 }, allow_nil: true
  validates :state, inclusion: { in: STATES }
  validates :timer_duration_seconds, numericality: { only_integer: true, greater_than: 0, less_than_or_equal_to: 5.hours.to_i }, allow_nil: true
  validates :pre_core_duration_seconds, :hangout_duration_seconds,
    numericality: { only_integer: true, greater_than_or_equal_to: 0, less_than_or_equal_to: 5.hours.to_i }
  validates :finish_reason, inclusion: { in: %w[manual automatic] }, allow_nil: true
  validate :configured_duration_fits_safety_window
  validate :scheduled_end_follows_start
  validate :meet_url_is_canonical
  validate :time_zone_is_supported

  scope :active, -> { where(state: ACTIVE_STATES) }

  def active? = state.in?(ACTIVE_STATES)
  def paused? = pauses.where(ended_at: nil).exists?
  def joinable? = state == "ready" || active?
  def run_token = started_at&.iso8601(6)

  def meeting_code
    GoogleWorkspace::MeetLink.code(meet_url) if GoogleWorkspace::MeetLink.canonical?(meet_url)
  end

  def closing_duration_seconds = [ timer_duration_seconds / 30, 1 ].max
  def default_timer_minutes = ((scheduled_ends_at - scheduled_starts_at - 30.minutes) / 60).round.clamp(1, 300)
  def default_pre_core_minutes = 10
  def default_hangout_minutes = 30

  def core_duration_minutes
    core_ends_at = hangout_started_at || ended_at
    return default_timer_minutes unless started_at && core_ends_at

    (normalized_timer_seconds(core_ends_at - (builder_updates_started_at || started_at)) / 60).floor
  end

  def ready_attendances
    builders = User.active.where(facilitator: false).order(:name, :email).to_a
    saved_attendances_by_user_id = attendances.where(user_id: builders.map(&:id)).index_by(&:user_id)

    builders.map do |builder|
      saved_attendances_by_user_id[builder.id] || BuilderSessionAttendance.new(
        builder_session: self,
        user: builder,
        display_name: builder.name.presence || "Builder",
        role: "builder",
        status: "present"
      )
    end
  end

  def mark_present!(user, at: Time.current, random: Random, expected_started_at: run_token)
    with_lock do
      return false if expected_started_at.present? ? !same_timer_run?(expected_started_at) : active?

      attendance = attendance_for!(user)
      was_absent = attendance.status == "absent"
      arrived_at = attendance.arrived_at || at if active?
      attendance.update!(status: "present", arrived_at: arrived_at || attendance.arrived_at)
      if state == "builder_updates" && attendance.role == "builder" && was_absent && attendance.speaker_state != "completed"
        insert_late_speaker!(attendance, at:, random:)
      end
      touch
    end
    self
  end

  def mark_absent!(user, at: Time.current, expected_started_at: run_token)
    with_lock do
      return false if expected_started_at.present? ? !same_timer_run?(expected_started_at) : active?

      attendance = attendance_for!(user)
      was_current = attendance.speaker_state == "speaking"
      attendance.assign_attributes(status: "absent")
      if was_current
        attendance.assign_attributes(speaker_state: "skipped", speaker_ended_at: at)
      elsif attendance.speaker_state == "queued"
        attendance.assign_attributes(speaker_state: nil, speaker_position: nil)
      end
      attendance.save!
      if was_current
        if (next_speaker = attendances.where(speaker_state: "queued").order(:speaker_position).first)
          start_speaker!(next_speaker, at:)
        end
      elsif state == "builder_updates"
        distribute_remaining_speaker_time!(at:)
      end
      touch
    end
    self
  end

  def advance_phase!(expected_state: nil, expected_started_at: run_token, at: Time.current, random: Random)
    with_lock do
      return false unless same_timer_run?(expected_started_at)
      return false if paused? || (expected_state && state != expected_state)

      case state
      when "connection" then begin_builder_updates!(at:, random:)
      when "builder_updates", "closing" then begin_hangout!(at:)
      else false
      end
    end
  end

  def pause!(at: Time.current, expected_started_at: run_token)
    with_lock do
      return false unless active? && same_timer_run?(expected_started_at)

      unless paused?
        pauses.create!(started_at: at)
        touch
      end
    end
    self
  end

  def resume!(at: Time.current, expected_started_at: run_token)
    with_lock do
      return false unless active? && same_timer_run?(expected_started_at)

      touch if close_open_pause!(at:)
    end
    self
  end

  def finish!(reason: "manual", at: Time.current, expected_started_at: nil)
    with_lock do
      return false unless active?
      return false if expected_started_at && !same_timer_run?(expected_started_at)

      close_open_pause!(at:)
      current_speaker&.update!(speaker_state: "skipped", speaker_ended_at: at)
      update!(state: "completed", finish_reason: reason, ended_at: at)
      create_transcript!(state: "pending") unless transcript
    end
    self
  end

  def cancel_start!(expected_started_at:)
    program.with_lock do
      with_lock do
        return false unless active? && same_timer_run?(expected_started_at)

        attendances.where(role: "facilitator").destroy_all
        attendances.where(role: "builder").update_all(
          arrived_at: nil,
          speaker_state: nil,
          speaker_position: nil,
          speaker_allotted_seconds: nil,
          speaker_started_at: nil,
          speaker_ended_at: nil,
          speaker_paused_seconds: 0,
          updated_at: Time.current
        )
        pauses.destroy_all
        update!(
          assigned_facilitator: program.main_facilitator,
          state: "ready",
          facilitator_name_snapshot: nil,
          started_at: nil,
          builder_updates_started_at: nil,
          closing_started_at: nil,
          hangout_started_at: nil,
          ended_at: nil,
          timer_duration_seconds: nil,
          pre_core_duration_seconds: 0,
          hangout_duration_seconds: 0,
          finish_reason: nil
        )
      end
    end
    true
  end

  def correct_times!(started_at:, ended_at:)
    with_lock do
      corrected_start = started_at&.change(usec: 0)
      corrected_end = ended_at&.change(usec: 0)
      recorded_phase_times = [ builder_updates_started_at, closing_started_at, hangout_started_at ].compact
        .map { |phase_time| phase_time.change(usec: 0) }
      valid_times = state == "completed" && corrected_start && corrected_end &&
        corrected_end.between?(corrected_start, corrected_start + 5.hours) &&
        recorded_phase_times.all? { |phase_time| phase_time.between?(corrected_start, corrected_end) }
      unless valid_times
        errors.add(:base, "Session times must contain every recorded phase and span no more than five hours")
        raise ActiveRecord::RecordInvalid, self
      end

      update!(started_at:, ended_at:)
    end
    self
  end

  def phase_remaining_seconds(at: Time.current)
    case state
    when "connection"
      [ normalized_timer_seconds(pre_core_duration_seconds - effective_elapsed_seconds(at:)).ceil, 0 ].max
    when "builder_updates"
      normalized_timer_seconds(scheduled_core_end_at(at:) - at).ceil
    when "closing"
      [ normalized_timer_seconds(closing_duration_seconds - effective_seconds_since(closing_started_at, at:)).ceil, 0 ].max
    else
      0
    end
  end

  def clock_mode = state == "hangout" && hangout_duration_seconds.zero? ? "countup" : "countdown"

  def clock_seconds(at: Time.current)
    if state == "hangout"
      hangout_elapsed = effective_seconds_since(hangout_started_at, at:)
      hangout_duration_seconds.zero? ? normalized_timer_seconds(hangout_elapsed).floor : hangout_duration_seconds - normalized_timer_seconds(hangout_elapsed).ceil
    elsif state == "builder_updates" && current_speaker
      current_speaker.speaker_allotted_seconds - normalized_timer_seconds(effective_seconds_since(current_speaker.speaker_started_at, at:)).ceil
    else
      phase_remaining_seconds(at:)
    end
  end

  def total_remaining_seconds(at: Time.current)
    state == "builder_updates" ? phase_remaining_seconds(at:) : 0
  end

  def current_speaker_attendance = current_speaker

  def unspoken_speakers
    attendances.where(role: "builder", status: "present", speaker_state: "queued").order(:speaker_position)
  end

  def reorder_unspoken_speakers!(attendance_ids, expected_started_at: run_token)
    with_lock do
      return false unless same_timer_run?(expected_started_at)

      requested_ids = attendance_ids.is_a?(Array) ? attendance_ids.map { |id| Integer(id, exception: false) } : []
      speakers = unspoken_speakers.to_a
      current_ids = speakers.map(&:id)
      valid_order = requested_ids.none?(&:nil?) &&
        requested_ids.uniq.length == requested_ids.length &&
        requested_ids.sort == current_ids.sort
      raise InvalidSpeakerOrder unless state == "builder_updates" && valid_order

      positions = speakers.map(&:speaker_position)
      speakers_by_id = speakers.index_by(&:id)
      temporary_offset = attendances.maximum(:speaker_position)
      speakers.each { |speaker| speaker.update!(speaker_position: speaker.speaker_position + temporary_offset) }
      requested_ids.zip(positions).each do |id, position|
        speakers_by_id.fetch(id).update!(speaker_position: position)
      end
      touch
    end
    self
  end

  def synchronize!(at: Time.current, random: Random)
    with_lock do
      if started_at && at >= started_at + 5.hours
        finish!(reason: "automatic", at: started_at + 5.hours)
        return self
      end
      return self if paused?

      loop do
        transitioned = case state
        when "connection"
          connection_ends_at = started_at + pre_core_duration_seconds + paused_duration_seconds(at:)
          begin_builder_updates!(at: connection_ends_at, random:) if at >= connection_ends_at
        when "builder_updates"
          core_ends_at = scheduled_core_end_at(at:)
          begin_hangout!(at: core_ends_at) if at >= core_ends_at
        when "closing"
          closing_ends_at = closing_started_at + closing_duration_seconds + paused_duration_since(closing_started_at, at:)
          begin_hangout!(at: closing_ends_at) if at >= closing_ends_at
        end
        break unless transitioned
      end
    end
    self
  end

  def finish_current_speaker!(expected_speaker_id: nil, expected_started_at: run_token, at: Time.current)
    with_lock do
      return false unless same_timer_run?(expected_started_at)

      synchronize!(at:)
      return false unless state == "builder_updates"

      speaker = current_speaker
      return false if expected_speaker_id && speaker&.id != expected_speaker_id

      speaker&.update!(speaker_state: "completed", speaker_ended_at: at)
      if (next_speaker = attendances.where(speaker_state: "queued").order(:speaker_position).first)
        start_speaker!(next_speaker, at:)
      else
        begin_hangout!(at:)
      end
      touch
      true
    end
  end

  def start!(facilitator:, duration_seconds: nil, pre_core_duration_seconds: 0, hangout_duration_seconds: 0, random: Random)
    program.with_lock do
      with_lock do
        raise AlreadyActive if program.builder_sessions.active.where.not(id: id).exists?
        raise ActiveRecord::RecordInvalid, self unless state == "ready"

        duration = duration_seconds || default_timer_minutes.minutes.to_i
        started_at = Time.current
        update!(
          assigned_facilitator: facilitator,
          facilitator_name_snapshot: facilitator.name.presence || "Facilitator",
          started_at:,
          state: "connection",
          timer_duration_seconds: duration,
          pre_core_duration_seconds:,
          hangout_duration_seconds:
        )
        snapshot_expected_attendees!(facilitator)
        begin_builder_updates!(at: started_at, random:) if pre_core_duration_seconds.zero?
      end
    end
    self
  rescue ActiveRecord::RecordNotUnique
    raise AlreadyActive
  end

  private

  def same_timer_run?(expected_started_at)
    expected_started_at.present? && run_token == expected_started_at
  end

  def normalized_timer_seconds(seconds)
    seconds.round(3)
  end

  def attendance_for!(user)
    attendances.find_by(user:) || begin
      raise ActiveRecord::RecordNotFound unless state == "ready" && user.active? && !user.facilitator?

      attendances.create!(
        user:,
        display_name: user.name.presence || "Builder",
        role: "builder",
        status: "absent"
      )
    end
  end

  def begin_builder_updates!(at:, random: Random)
    update!(state: "builder_updates", builder_updates_started_at: at)
    queued = attendances.where(role: "builder", status: "present", speaker_state: nil).to_a.shuffle(random:)
    queued.each_with_index do |attendance, index|
      attendance.update!(speaker_state: "queued", speaker_position: index + 1)
    end
    if queued.first
      start_speaker!(queued.first, at:)
    elsif !attendances.where(role: "builder").exists?
      begin_hangout!(at:)
    end
    true
  end

  def begin_hangout!(at:)
    current_speaker&.update!(speaker_state: "skipped", speaker_ended_at: at)
    attendances.where(speaker_state: "queued").update_all(speaker_state: "skipped", updated_at: Time.current)
    update!(state: "hangout", hangout_started_at: at)
    true
  end

  def insert_late_speaker!(attendance, at:, random:)
    attendance.update!(
      speaker_state: nil,
      speaker_position: nil,
      speaker_started_at: nil,
      speaker_ended_at: nil,
      speaker_allotted_seconds: nil
    )
    queued = unspoken_speakers.to_a
    insertion_index = random.rand(queued.length + 1)
    insertion_position = queued[insertion_index]&.speaker_position || attendances.maximum(:speaker_position).to_i + 1
    queued.reverse_each do |speaker|
      speaker.update!(speaker_position: speaker.speaker_position + 1) if speaker.speaker_position >= insertion_position
    end
    attendance.update!(
      speaker_state: "queued",
      speaker_position: insertion_position
    )
    if current_speaker
      distribute_remaining_speaker_time!(at:)
    else
      start_speaker!(unspoken_speakers.first, at:)
    end
  end

  def start_speaker!(attendance, at:)
    attendance.update!(speaker_state: "speaking", speaker_started_at: at)
    distribute_remaining_speaker_time!(at:)
  end

  def distribute_remaining_speaker_time!(at:)
    speakers = attendances.where(speaker_state: %w[speaking queued]).order(:speaker_position).to_a
    return if speakers.empty?

    available_seconds = [ normalized_timer_seconds(scheduled_core_end_at(at:) - at).ceil, 0 ].max
    seconds_per_speaker, extra_seconds = available_seconds.divmod(speakers.length)
    speakers.each_with_index do |speaker, index|
      remaining_seconds = seconds_per_speaker + (index < extra_seconds ? 1 : 0)
      elapsed_seconds = speaker.speaker_state == "speaking" ? normalized_timer_seconds(effective_seconds_since(speaker.speaker_started_at, at:)).ceil : 0
      speaker.update!(speaker_allotted_seconds: elapsed_seconds + remaining_seconds)
    end
  end

  def current_speaker
    attendances.find_by(speaker_state: "speaking")
  end

  def scheduled_core_end_at(at:)
    builder_updates_started_at + timer_duration_seconds + paused_duration_since(builder_updates_started_at, at:)
  end

  def effective_elapsed_seconds(at:)
    at - started_at - paused_duration_seconds(at:)
  end

  def effective_seconds_since(timestamp, at:)
    at - timestamp - paused_duration_since(timestamp, at:)
  end

  def paused_duration_seconds(at:)
    paused_duration_since(started_at, at:)
  end

  def paused_duration_since(timestamp, at:)
    pauses.sum do |pause|
      pause_start = [ pause.started_at, timestamp ].max
      pause_end = [ pause.ended_at || at, at ].min
      [ pause_end - pause_start, 0 ].max
    end
  end

  def close_open_pause!(at:)
    pause = pauses.find_by(ended_at: nil)
    return unless pause

    duration = [ at - pause.started_at, 0 ].max.to_i
    current_speaker&.increment!(:speaker_paused_seconds, duration)
    pause.update!(ended_at: at)
  end

  def snapshot_expected_attendees!(facilitator)
    expected = User.active.where(facilitator: false).to_a
    expected_ids = expected.map(&:id)
    attendances.where(role: "builder").find_each do |attendance|
      attendance.destroy! unless attendance.user_id.in?(expected_ids)
    end
    expected << facilitator unless expected.include?(facilitator)
    expected.each do |user|
      attendance = attendances.find_or_initialize_by(user: user)
      attendance.display_name = user.name.presence || (user == facilitator ? "Facilitator" : "Builder")
      attendance.role = user == facilitator || user.facilitator? ? "facilitator" : "builder"
      if user == facilitator
        attendance.status = "present"
        attendance.arrived_at ||= started_at
      elsif attendance.new_record?
        attendance.status = "present"
      end
      attendance.save!
    end
  end

  def scheduled_end_follows_start
    return unless scheduled_starts_at && scheduled_ends_at && scheduled_ends_at <= scheduled_starts_at

    errors.add(:scheduled_ends_at, "must be after the start time")
  end

  def meet_url_is_canonical
    errors.add(:meet_url, "must be a canonical Google Meet URL") if meet_url.present? && !GoogleWorkspace::MeetLink.canonical?(meet_url)
  end

  def time_zone_is_supported
    errors.add(:time_zone, "must be a supported time zone") if time_zone.present? && ActiveSupport::TimeZone[time_zone].nil?
  end

  def configured_duration_fits_safety_window
    return unless timer_duration_seconds && pre_core_duration_seconds && hangout_duration_seconds
    return if timer_duration_seconds + pre_core_duration_seconds + hangout_duration_seconds <= 5.hours.to_i

    errors.add(:base, "Configured session phases must fit within five hours")
  end
end
