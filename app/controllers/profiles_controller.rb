class ProfilesController < ApplicationController
  before_action :require_user

  def edit
    @product = current_user.focus_product || Product.new(user: current_user)
  end

  def update
    current_user.transaction do
      current_user.assign_attributes(user_params)
      save_focus_product
      current_user.save!
    end
    redirect_to dashboard_path, notice: "Your profile is updated."
  rescue ActiveRecord::RecordInvalid
    @product = current_user.focus_product || Product.new(user: current_user)
    render :edit, status: :unprocessable_content
  end

  def destroy
    current_user.destroy!
    reset_session
    redirect_to root_path, notice: "Your Rails Builders account has been deleted."
  end

  private

  def user_params
    params.require(:user).permit(:name, :testimonial, :public_profile, :avatar)
  end

  def save_focus_product
    attributes = params.fetch(:product, {}).permit(:name, :url)
    return if attributes[:name].blank? && attributes[:url].blank?

    product = current_user.focus_product || Product.new(user: current_user)
    product.update!(attributes)
    product.make_focus!
  end
end
