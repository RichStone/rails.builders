class Admin::DashboardController < Admin::BaseController
  def index
    # A native same-origin form POST otherwise sends Origin: null under no-referrer.
    response.set_header("Referrer-Policy", "same-origin")
    @program = Program.current
    @calendar_connection = @program.calendar_connection
    @users = User.order(:waitlist_rank, :created_at)
    @og_builders = @users.where(og: true)
    @waitlist_builders = @users.where(og: false)
  end
end
