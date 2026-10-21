class DashboardController < ApplicationController
  before_action :require_user

  def show
    @program = Program.current
    @next_session = @program.builder_sessions.active.first || @program.builder_sessions.upcoming.first if current_user.active?
  end
end
