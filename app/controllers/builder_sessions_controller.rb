class BuilderSessionsController < ApplicationController
  before_action :require_session_member
  before_action :require_session_operator, only: %i[sync_calendar start cancel_start pause resume advance next_speaker finish attendance speaker_order timing]
  before_action :set_builder_session, only: %i[show join start cancel_start pause resume advance next_speaker finish attendance speaker_order timing heartbeat]
  before_action :queue_stale_calendar_sync, only: :index

  def index
    sessions = Program.current.builder_sessions
    now = Time.current
    @live_session = sessions.active.first
    @upcoming_sessions = sessions.where(state: "ready", scheduled_starts_at: now..).order(:scheduled_starts_at)
    @past_sessions = sessions.where(state: %w[completed cancelled])
      .or(sessions.where(state: "ready", scheduled_starts_at: ...now))
      .order(scheduled_starts_at: :desc)
  end

  def show; end

  def join
    return redirect_to(@builder_session, alert: "This session is not open for joining.") unless @builder_session.joinable?

    meeting_code = @builder_session.meeting_code
    return redirect_to(@builder_session, alert: "This session does not have a Google Meet link.") unless meeting_code

    destination = URI::HTTPS.build(host: "meet.google.com", path: "/#{meeting_code}")
    redirect_to destination.to_s, allow_other_host: true
  end

  def sync_calendar
    connection = Program.current.calendar_connection
    if connection&.status == "connected"
      GoogleCalendarSyncJob.perform_later(connection.id)
      redirect_to builder_sessions_path, notice: "Calendar sync queued."
    else
      redirect_to builder_sessions_path, alert: "The Sessions calendar needs an Administrator to reconnect it."
    end
  end

  def start
    pre_core_minutes = params[:pre_core_minutes].nil? ? 0 : Integer(params[:pre_core_minutes], exception: false)
    core_minutes = params[:duration_minutes].nil? ? @builder_session.default_timer_minutes : Integer(params[:duration_minutes], exception: false)
    hangout_minutes = params[:hangout_minutes].nil? ? 0 : Integer(params[:hangout_minutes], exception: false)
    valid_durations = pre_core_minutes&.between?(0, 300) && core_minutes&.between?(1, 300) &&
      hangout_minutes&.between?(0, 300) && pre_core_minutes + core_minutes + hangout_minutes <= 300
    return redirect_to(@builder_session, alert: "Choose valid session phase lengths.") unless valid_durations

    @builder_session.start!(
      facilitator: current_user,
      duration_seconds: core_minutes.minutes.to_i,
      pre_core_duration_seconds: pre_core_minutes.minutes.to_i,
      hangout_duration_seconds: hangout_minutes.minutes.to_i
    )
    redirect_to @builder_session, notice: "Session started."
  rescue BuilderSession::AlreadyActive, ActiveRecord::RecordInvalid
    redirect_to builder_sessions_path, alert: "The session could not be started."
  end

  def cancel_start
    cancelled = @builder_session.cancel_start!(expected_started_at: params[:run_started_at])
    redirect_to @builder_session,
      (cancelled ? { notice: "Mistaken session start discarded." } : { alert: "That session run had already changed." })
  end

  def pause
    paused = params[:run_started_at].present? &&
      @builder_session.pause!(expected_started_at: params[:run_started_at])
    redirect_to @builder_session,
      (paused ? { notice: "Session paused." } : { alert: "That session run had already changed." })
  end

  def resume
    resumed = params[:run_started_at].present? &&
      @builder_session.resume!(expected_started_at: params[:run_started_at])
    redirect_to @builder_session,
      (resumed ? { notice: "Session resumed." } : { alert: "That session run had already changed." })
  end

  def advance
    advanced = params[:state].present? && params[:run_started_at].present? &&
      @builder_session.advance_phase!(expected_state: params[:state], expected_started_at: params[:run_started_at])
    redirect_to @builder_session, (advanced ? { notice: "Session advanced." } : { alert: "The session had already moved on." })
  end

  def next_speaker
    speaker_id = Integer(params[:speaker_id], exception: false)
    completed = speaker_id && params[:run_started_at].present? &&
      @builder_session.finish_current_speaker!(expected_speaker_id: speaker_id, expected_started_at: params[:run_started_at])
    redirect_to @builder_session, (completed ? { notice: "Speaker completed." } : { alert: "That speaker had already been completed." })
  end

  def finish
    finished = params[:run_started_at].present? && @builder_session.finish!(expected_started_at: params[:run_started_at])
    redirect_to @builder_session,
      (finished ? { notice: "Session finished." } : { alert: "That session run had already changed." })
  end

  def attendance
    user = User.find(params[:user_id])
    changed = if params[:status] == "present"
      @builder_session.mark_present!(user, expected_started_at: params[:run_started_at])
    else
      @builder_session.mark_absent!(user, expected_started_at: params[:run_started_at])
    end
    redirect_to @builder_session, (changed ? {} : { alert: "That session run had already changed." })
  end

  def speaker_order
    reordered = params[:run_started_at].present? && @builder_session.reorder_unspoken_speakers!(
      params[:attendance_ids],
      expected_started_at: params[:run_started_at]
    )
    return head :conflict unless reordered

    render json: { version: @builder_session.reload.updated_at.iso8601(6) }
  rescue BuilderSession::InvalidSpeakerOrder
    head :unprocessable_entity
  end

  def timing
    zone = ActiveSupport::TimeZone[@builder_session.time_zone]
    corrected_start = zone&.parse(params[:started_at].to_s)
    corrected_end = zone&.parse(params[:ended_at].to_s)
    @builder_session.correct_times!(started_at: corrected_start, ended_at: corrected_end)
    redirect_to @builder_session, notice: "Session times corrected."
  rescue ActiveRecord::RecordInvalid, ArgumentError
    redirect_to @builder_session, alert: "The session times could not be corrected."
  end

  def heartbeat
    @builder_session.synchronize!
    render json: {
      state: @builder_session.state,
      paused: @builder_session.paused?,
      version: @builder_session.updated_at.iso8601(6)
    }
  end

  private

  def set_builder_session
    @builder_session = Program.current.builder_sessions.find(params[:id])
  end

  def queue_stale_calendar_sync
    return unless session_operator?

    connection = Program.current.calendar_connection
    return unless connection&.status == "connected"
    return if connection.last_synced_at && connection.last_synced_at > 75.minutes.ago

    Rails.cache.fetch("sessions-calendar-sync-queued-#{connection.id}", expires_in: 10.minutes) do
      GoogleCalendarSyncJob.perform_later(connection.id)
      true
    end
  end
end
