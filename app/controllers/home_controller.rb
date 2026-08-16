class HomeController < ApplicationController
  def index
    @program = Program.current
    @facilitators = User.where(facilitator: true).publicly_visible
    @active_builders = User.active
    @waitlisted_builders = User.waitlisted.publicly_visible
    @og_builders = User.og.where.not(enrollment_status: "active").where.not(id: @waitlisted_builders.select(:id))
  end

  def privacy; end
end
