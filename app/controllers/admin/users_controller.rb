class Admin::UsersController < Admin::BaseController
  before_action :set_user

  def edit; end

  def update
    program = Program.current
    attributes = user_params
    program.with_lock do
      @user.public_profile_approved = false if (attributes.keys & %w[name testimonial avatar public_profile]).any?
      @user.update!(attributes)
    end
    program.promote_waitlist! unless program.og_priority?
    redirect_to admin_root_path, notice: "Builder updated."
  end

  def destroy
    @user.destroy!
    redirect_to admin_root_path, notice: "Builder deleted."
  end

  def retry_newsletter
    if @user.verified? && @user.newsletter_confirmed_at?
      @user.update!(clickfunnels_sync_status: "pending")
      ClickfunnelsNewsletterJob.perform_later(@user.id)
      redirect_to edit_admin_user_path(@user), notice: "Newsletter sync queued."
    else
      redirect_to edit_admin_user_path(@user), alert: "Both email confirmations are required first."
    end
  end

  private

  def set_user
    @user = User.find(params[:id])
  end

  def user_params
    params.require(:user).permit(:email, :name, :testimonial, :avatar, :public_profile, :og, :administrator, :facilitator, :enrollment_status, :waitlist_rank, :slack_status)
  end
end
