class BuilderSessionsController < ApplicationController
  before_action :require_session_member
  before_action :require_session_operator, only: %i[sync_calendar start pause resume advance next_speaker finish attendance speaker_order end_time]
  before_action :set_builder_session, only: %i[show join start pause resume advance next_speaker finish attendance speaker_order end_time heartbeat]
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
    duration_minutes = Integer(params[:duration_minutes], exception: false)
    duration_seconds = duration_minutes&.between?(1, 300) ? duration_minutes.minutes.to_i : nil
    @builder_session.start!(facilitator: current_user, duration_seconds:)
    redirect_to @builder_session, notice: "Session started."
  rescue BuilderSession::AlreadyActive, ActiveRecord::RecordInvalid
    redirect_to builder_sessions_path, alert: "The session could not be started."
  end

  def pause
    @builder_session.pause!
    redirect_to @builder_session, notice: "Session paused."
  end

  def resume
    @builder_session.resume!
    redirect_to @builder_session, notice: "Session resumed."
  end

  def advance
    @builder_session.advance_phase!
    redirect_to @builder_session, notice: "Session advanced."
  end

  def next_speaker
    @builder_session.finish_current_speaker!
    redirect_to @builder_session, notice: "Speaker completed."
  end

  def finish
    @builder_session.finish!
    redirect_to @builder_session, notice: "Session finished."
  end

  def attendance
    user = User.find(params[:user_id])
    if params[:status] == "present"
      @builder_session.mark_present!(user)
    else
      @builder_session.mark_absent!(user)
    end
    redirect_to @builder_session
  end

  def speaker_order
    @builder_session.reorder_unspoken_speakers!(params[:attendance_ids])
    head :no_content
  rescue BuilderSession::InvalidSpeakerOrder
    head :unprocessable_entity
  end

  def end_time
    zone = ActiveSupport::TimeZone[@builder_session.time_zone]
    corrected_end = zone&.parse(params[:ended_at].to_s)
    @builder_session.correct_automatic_end!(corrected_end)
    redirect_to @builder_session, notice: "Session end time corrected."
  rescue ActiveRecord::RecordInvalid, ArgumentError
    redirect_to @builder_session, alert: "The session end time could not be corrected."
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
