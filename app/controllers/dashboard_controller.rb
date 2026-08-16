class DashboardController < ApplicationController
  before_action :require_user

  def show
    @program = Program.current
  end
end
