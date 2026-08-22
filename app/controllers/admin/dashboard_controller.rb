class Admin::DashboardController < Admin::BaseController
  def index
    @program = Program.current
    @calendar_connection = @program.calendar_connection
    @users = User.order(:waitlist_rank, :created_at)
  end
end
