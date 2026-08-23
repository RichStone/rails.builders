class HomeController < ApplicationController
  def index
    @program = Program.current
    @facilitators = User.where(facilitator: true).publicly_visible
    @active_builders = User.active
    @waitlisted_builders = User.waitlisted
    @og_builders = User.og.where.not(enrollment_status: "active").where.not(id: @waitlisted_builders.select(:id))
    sessions = @program.builder_sessions
    @live_session = sessions.active.first
    @upcoming_sessions = sessions.where(state: "ready", scheduled_starts_at: Time.current..).order(:scheduled_starts_at).limit(3)
  end

  def privacy; end
  def terms; end
end
