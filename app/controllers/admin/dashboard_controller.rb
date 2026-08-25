class Admin::DashboardController < Admin::BaseController
  def index
    # A native same-origin form POST otherwise sends Origin: null under no-referrer.
    response.set_header("Referrer-Policy", "same-origin")
    @program = Program.current
    @calendar_connection = @program.calendar_connection
    @users = User.order(:waitlist_rank, :created_at)
    builders_by_status = @users.group_by(&:enrollment_status)
    statuses = %w[active waitlisted] | User::ENROLLMENT_STATUSES
    @builder_groups = statuses.filter_map do |status|
      [ status, builders_by_status[status] ] if builders_by_status.key?(status)
    end
  end
end
