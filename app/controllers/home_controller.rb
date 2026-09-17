class HomeController < ApplicationController
  def index
    @program = Program.current
    @facilitators = User.where(facilitator: true).publicly_visible.avatar_first
    @active_builders = User.active.avatar_first
    @waitlisted_builders = User.waitlisted.avatar_first
    inactive_builders = User.where.not(verified_at: nil).where(enrollment_status: User::WAITLIST_ELIGIBLE_STATUSES)
    @inactive_builders = inactive_builders.avatar_first
    @past_builders = User.og.where.not(enrollment_status: %w[active waitlisted]).where.not(id: inactive_builders.select(:id)).avatar_first
    sessions = @program.builder_sessions
    @live_session = sessions.active.first
    @upcoming_sessions = sessions.where(state: "ready", scheduled_starts_at: Time.current..).order(:scheduled_starts_at).limit(3)
  end

  def privacy; end
  def terms; end
end
