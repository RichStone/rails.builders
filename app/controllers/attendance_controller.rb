class AttendanceController < ApplicationController
  before_action :require_session_member

  def show
    @program = Program.current
    @builder_sessions = @program.builder_sessions.where(state: "completed").order(:scheduled_starts_at, :id).to_a
    records = BuilderSessionAttendance.where(builder_session_id: @builder_sessions.map(&:id)).where.not(user_id: nil).to_a
    @attendance_by_user = records.group_by(&:user_id).transform_values { |attendances| attendances.index_by(&:builder_session_id) }
    @builders = User.active
      .or(User.where(facilitator: true).where.not(enrollment_status: "removed"))
      .or(User.where(id: @attendance_by_user.keys)).order(:name, :id)
    @present_count = records.count { |attendance| attendance.status == "present" }
    @missed_count = records.size - @present_count
    @recorded_count = records.size
  end
end
