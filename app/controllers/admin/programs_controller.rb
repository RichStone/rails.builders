class Admin::ProgramsController < Admin::BaseController
  before_action :set_program

  def update
    attributes = program_params
    old_main_facilitator_id = @program.main_facilitator_id
    requested_facilitator_id = attributes[:main_facilitator_id].presence&.to_i
    facilitator_changed = attributes.key?(:main_facilitator_id) && requested_facilitator_id != old_main_facilitator_id
    if facilitator_changed && facilitator_handoff_blocked?
      return redirect_to admin_root_path,
        alert: "Finish the live session and wait for its automatic transcript before changing the main facilitator."
    end

    @program.with_lock { @program.update!(attributes) }
    facilitator_changed = @program.main_facilitator_id != old_main_facilitator_id
    disconnect_calendar_after_facilitator_handoff if facilitator_changed
    @program.promote_waitlist! unless @program.og_priority?
    notice = facilitator_changed ? "Program updated. Reconnect the Sessions calendar for the new main facilitator." : "Program updated."
    redirect_to admin_root_path, notice:
  end

  def promote
    @program.promote_waitlist!
    redirect_to admin_root_path, notice: "The waitlist was checked for available seats."
  end

  def expire_offers
    @program.expire_offers!
    redirect_to admin_root_path, notice: "Expired offers were released."
  end

  private

  def set_program
    @program = Program.find(params[:id])
  end

  def program_params
    attributes = params.require(:program).permit(:name, :starts_on, :starts_at_time, :ends_on, :ends_at_time, :capacity, :format_points, :readiness_points, :og_priority, :promotions_paused, :main_facilitator_id)
    assign_boundary_time(attributes, :starts_at)
    assign_boundary_time(attributes, :ends_at)
    attributes
  end

  def assign_boundary_time(attributes, timestamp)
    time_key = "#{timestamp}_time"
    return unless attributes.key?(time_key)

    time = attributes.delete(time_key)
    attributes[timestamp] = if time.present?
      date_attribute = timestamp == :starts_at ? :starts_on : :ends_on
      date = attributes[date_attribute].presence || @program.public_send(date_attribute)
      @program.schedule_zone.parse("#{date} #{time}")
    end
    attributes[:schedule_time_zone] = @program.schedule_zone.name
  end

  def disconnect_calendar_after_facilitator_handoff
    connection = @program.calendar_connection
    if connection
      begin
        GoogleWorkspace::Authorization.new(connection:).revoke!
      rescue StandardError => error
        Rails.logger.warn("Old facilitator Google token revocation failed (#{error.class.name})")
      end
      connection.destroy!
    end

    @program.builder_sessions.where(state: "ready").update_all(
      assigned_facilitator_id: @program.main_facilitator_id,
      meet_url: nil,
      updated_at: Time.current
    )
  end

  def facilitator_handoff_blocked?
    @program.calendar_credentials_in_use?
  end
end
