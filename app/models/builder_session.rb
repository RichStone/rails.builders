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
  validates :finish_reason, inclusion: { in: %w[manual automatic] }, allow_nil: true
  validate :scheduled_end_follows_start
  validate :meet_url_is_canonical
  validate :time_zone_is_supported

  scope :active, -> { where(state: ACTIVE_STATES) }

  def active? = state.in?(ACTIVE_STATES)
  def paused? = pauses.where(ended_at: nil).exists?
  def joinable? = state == "ready" || active?

  def meeting_code
    GoogleWorkspace::MeetLink.code(meet_url) if GoogleWorkspace::MeetLink.canonical?(meet_url)
  end

  def connection_duration_seconds = timer_duration_seconds / 6
  def closing_duration_seconds = [ timer_duration_seconds / 30, 1 ].max
  def default_timer_minutes = ((scheduled_ends_at - scheduled_starts_at) / 90).round.clamp(1, 300)

  def mark_present!(user, at: Time.current)
    with_lock do
      attendance = attendances.find_by!(user: user)
      arrived_at = attendance.arrived_at || at unless state == "completed"
      attendance.update!(status: "present", arrived_at: arrived_at || attendance.arrived_at)
      append_late_speaker!(attendance, at:) if state == "builder_updates" && attendance.role == "builder" && attendance.speaker_state.nil?
      touch
    end
  end

  def mark_absent!(user, at: Time.current)
    with_lock do
      attendance = attendances.find_by!(user: user)
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
        else
          begin_closing!(at:)
        end
      elsif state == "builder_updates"
        recalculate_current_allotment!(at:)
      end
      touch
    end
    self
  end

  def advance_phase!(at: Time.current)
    with_lock do
      return self if paused?

      case state
      when "connection" then begin_builder_updates!(at:)
      when "builder_updates" then begin_closing!(at:)
      when "closing" then begin_hangout!(at:)
      when "hangout" then finish!(at:)
      end
    end
    self
  end

  def pause!(at: Time.current)
    with_lock do
      return self unless active?

      unless paused?
        pauses.create!(started_at: at)
        touch
      end
    end
    self
  end

  def resume!(at: Time.current)
    with_lock do
      touch if close_open_pause!(at:)
    end
    self
  end

  def finish!(reason: "manual", at: Time.current)
    with_lock do
      return self unless active?

      close_open_pause!(at:)
      current_speaker&.update!(speaker_state: "skipped", speaker_ended_at: at)
      update!(state: "completed", finish_reason: reason, ended_at: at)
      create_transcript!(state: "pending") unless transcript
    end
    self
  end

  def correct_automatic_end!(value)
    with_lock do
      valid_end = state == "completed" && finish_reason == "automatic" && started_at &&
        value && value >= started_at && value <= started_at + 5.hours
      unless valid_end
        errors.add(:ended_at, "must fall between the automatic session start and close")
        raise ActiveRecord::RecordInvalid, self
      end

      update!(ended_at: value)
    end
    self
  end

  def phase_remaining_seconds(at: Time.current)
    case state
    when "connection"
      [ (connection_duration_seconds - effective_elapsed_seconds(at:)).ceil, 0 ].max
    when "builder_updates"
      (scheduled_closing_at(at:) - at).ceil
    when "closing"
      [ (closing_duration_seconds - effective_seconds_since(closing_started_at, at:)).ceil, 0 ].max
    else
      0
    end
  end

  def clock_mode = state == "hangout" ? "countup" : "countdown"

  def clock_seconds(at: Time.current)
    if state == "hangout"
      effective_seconds_since(hangout_started_at, at:).floor
    elsif state == "builder_updates" && current_speaker
      current_speaker.speaker_allotted_seconds - effective_seconds_since(current_speaker.speaker_started_at, at:).ceil
    else
      phase_remaining_seconds(at:)
    end
  end

  def total_remaining_seconds(at: Time.current)
    return 0 unless started_at

    (timer_duration_seconds - effective_elapsed_seconds(at:)).ceil
  end

  def current_speaker_attendance = current_speaker

  def unspoken_speakers
    attendances.where(role: "builder", status: "present", speaker_state: "queued").order(:speaker_position)
  end

  def reorder_unspoken_speakers!(attendance_ids)
    with_lock do
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

  def synchronize!(at: Time.current)
    with_lock do
      if started_at && at >= started_at + 5.hours
        finish!(reason: "automatic", at: started_at + 5.hours)
        return self
      end
      return self if paused?

      loop do
        transitioned = case state
        when "connection"
          connection_ends_at = started_at + connection_duration_seconds + paused_duration_seconds(at:)
          begin_builder_updates!(at: connection_ends_at) if at >= connection_ends_at
        when "builder_updates"
          closing_at = scheduled_closing_at(at:)
          begin_closing!(at: closing_at) if at >= closing_at
        when "closing"
          closing_ends_at = closing_started_at + closing_duration_seconds + paused_duration_since(closing_started_at, at:)
          begin_hangout!(at: closing_ends_at) if at >= closing_ends_at
        end
        break unless transitioned
      end
    end
    self
  end

  def finish_current_speaker!(at: Time.current)
    with_lock do
      synchronize!(at:)
      return self unless state == "builder_updates"

      current_speaker&.update!(speaker_state: "completed", speaker_ended_at: at)
      if (next_speaker = attendances.where(speaker_state: "queued").order(:speaker_position).first)
        start_speaker!(next_speaker, at:)
      else
        begin_closing!(at:)
      end
      touch
    end
    self
  end

  def start!(facilitator:, duration_seconds: nil)
    program.with_lock do
      with_lock do
        raise AlreadyActive if program.builder_sessions.active.where.not(id: id).exists?
        raise ActiveRecord::RecordInvalid, self unless state == "ready"

        duration = duration_seconds || default_timer_minutes.minutes.to_i
        update!(
          assigned_facilitator: facilitator,
          facilitator_name_snapshot: facilitator.name.presence || "Facilitator",
          started_at: Time.current,
          state: "connection",
          timer_duration_seconds: duration
        )
        snapshot_expected_attendees!(facilitator)
      end
    end
    self
  rescue ActiveRecord::RecordNotUnique
    raise AlreadyActive
  end

  private

  def begin_builder_updates!(at:)
    update!(state: "builder_updates", builder_updates_started_at: at)
    queued = attendances.where(role: "builder", status: "present", speaker_state: nil).to_a.shuffle
    queued.each_with_index do |attendance, index|
      attendance.update!(speaker_state: "queued", speaker_position: index + 1)
    end
    queued.first ? start_speaker!(queued.first, at:) : begin_closing!(at:)
    true
  end

  def begin_closing!(at:)
    current_speaker&.update!(speaker_state: "skipped", speaker_ended_at: at)
    update!(state: "closing", closing_started_at: at)
    true
  end

  def begin_hangout!(at:)
    update!(state: "hangout", hangout_started_at: at)
    true
  end

  def append_late_speaker!(attendance, at:)
    attendance.update!(
      speaker_state: "queued",
      speaker_position: attendances.maximum(:speaker_position).to_i + 1
    )
    recalculate_current_allotment!(at:)
  end

  def start_speaker!(attendance, at:)
    attendance.update!(speaker_state: "speaking", speaker_started_at: at)
    recalculate_current_allotment!(at:)
  end

  def recalculate_current_allotment!(at:)
    remaining = attendances.where(speaker_state: %w[queued speaking]).count
    return if remaining.zero? || current_speaker.nil?

    current_speaker.update!(speaker_allotted_seconds: [ ((scheduled_closing_at(at:) - at) / remaining).ceil, 0 ].max)
  end

  def current_speaker
    attendances.find_by(speaker_state: "speaking")
  end

  def scheduled_closing_at(at:)
    started_at + timer_duration_seconds - closing_duration_seconds + paused_duration_seconds(at:)
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
    expected << facilitator unless expected.include?(facilitator)
    expected.each do |user|
      attendance = attendances.find_or_initialize_by(user: user)
      attendance.display_name = user.name.presence || (user == facilitator ? "Facilitator" : "Builder")
      attendance.role = user == facilitator || user.facilitator? ? "facilitator" : "builder"
      if user == facilitator
        attendance.status = "present"
        attendance.arrived_at ||= started_at
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
end
