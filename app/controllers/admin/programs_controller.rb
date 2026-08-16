class Admin::ProgramsController < Admin::BaseController
  before_action :set_program

  def update
    @program.with_lock { @program.update!(program_params) }
    @program.promote_waitlist! unless @program.og_priority?
    redirect_to admin_root_path, notice: "Program updated."
  end

  def promote
    @program.promote_waitlist!
    redirect_to admin_root_path, notice: "The waitlist was checked for available seats."
  end

  def expire_offers
    @program.expire_offers!
    redirect_to admin_root_path, notice: "Expired offers were released."
  end

  private

  def set_program
    @program = Program.find(params[:id])
  end

  def program_params
    params.require(:program).permit(:name, :starts_on, :ends_on, :capacity, :og_priority, :promotions_paused)
  end
end
