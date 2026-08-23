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
    if @user.delete_account!
      redirect_to admin_root_path, notice: "Builder deleted."
    else
      redirect_to edit_admin_user_path(@user), alert: "The last verified Administrator cannot be deleted."
    end
  end

  def remove
    changed = @user.remove_from_program!
    redirect_to edit_admin_user_path(@user), notice: changed ? "Builder removed from Rails Builders." : "Builder was already removed."
  end

  def reinstate
    changed = @user.reinstate_enrollment!
    redirect_to edit_admin_user_path(@user), notice: changed ? "Enrollment eligibility reinstated." : "Builder is already eligible."
  end

  def grant_administrator
    @user.update_administrator_role!(administrator: true)
    redirect_to edit_admin_user_path(@user), notice: "Administrator role granted."
  end

  def revoke_administrator
    if @user.update_administrator_role!(administrator: false)
      redirect_to edit_admin_user_path(@user), notice: "Administrator role removed."
    else
      redirect_to edit_admin_user_path(@user), alert: "The last verified Administrator cannot be demoted."
    end
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
    params.require(:user).permit(:email, :name, :testimonial, :avatar, :public_profile, :og, :facilitator, :waitlist_rank, :slack_status)
  end
end
