class AttendanceController < ApplicationController
  before_action :require_session_member

  def show
    @program = Program.current
    @builder_sessions = @program.builder_sessions.where(state: %w[completed cancelled], scheduled_starts_at: ..Time.current)
      .order(:scheduled_starts_at, :id).to_a
    completed_sessions = @builder_sessions.select { |session| session.state == "completed" }
    @completed_count = completed_sessions.size
    records = BuilderSessionAttendance.where(builder_session_id: completed_sessions.map(&:id)).where.not(user_id: nil).to_a
    @attendance_by_user = records.group_by(&:user_id).transform_values { |attendances| attendances.index_by(&:builder_session_id) }
    @builders = User.active
      .or(User.where(facilitator: true).where.not(enrollment_status: "removed"))
      .or(User.where(id: @attendance_by_user.keys)).order(:name, :id)
    @absence_streaks = @builders.to_h do |builder|
      [ builder.id, BuilderSessionAttendance.absence_streak(sessions: completed_sessions,
        attendances: @attendance_by_user.fetch(builder.id, {}), reset_at: builder.attendance_streak_reset_at) ]
    end
    @present_count = records.count { |attendance| attendance.status == "present" }
    @missed_count = records.size - @present_count
    @recorded_count = records.size
  end
end
