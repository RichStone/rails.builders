class Admin::DashboardController < Admin::BaseController
  def index
    @program = Program.current
    @users = User.order(:waitlist_rank, :created_at)
  end
end
