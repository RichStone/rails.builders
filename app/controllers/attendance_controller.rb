class AttendanceController < ApplicationController
  before_action :require_session_member
  before_action :require_session_operator, only: :mark_strike_email_sent

  def show
    load_attendance
    @builders = User.active
      .or(User.where(facilitator: true).where.not(enrollment_status: "removed"))
      .or(User.where(id: @attendance_by_user.keys)).order(:name, :id)
    records = @attendance_by_user.values.flat_map(&:values)
    @present_count = records.count { |attendance| attendance.status == "present" }
    @missed_count = records.size - @present_count
    @recorded_count = records.size
  end

  def mark_strike_email_sent
    load_attendance
    streak = @absence_streaks.values.find { |attendances| attendances.first&.id == params[:attendance_id].to_i }
    unless streak && streak.size >= @program.consecutive_absence_limit
      return redirect_to attendance_path, alert: "Attendance has changed. Only a current streak at the limit can have its email marked sent."
    end

    streak.first.update!(strike_email_sent_at: Time.current) unless streak.any?(&:strike_email_sent_at)
    redirect_to attendance_path, notice: "Strike email marked sent."
  end

  private

  def load_attendance
    @program = Program.current
    @builder_sessions = @program.builder_sessions.where(state: "completed").order(:scheduled_starts_at, :id).to_a
    records = BuilderSessionAttendance.where(builder_session_id: @builder_sessions.map(&:id)).where.not(user_id: nil).to_a
    @attendance_by_user = records.group_by(&:user_id).transform_values { |attendances| attendances.index_by(&:builder_session_id) }
    @absence_streaks = @attendance_by_user.transform_values do |attendances|
      @builder_sessions.reverse_each.take_while { |session| attendances[session.id]&.status == "absent" }
        .map { |session| attendances.fetch(session.id) }
    end
  end
end
