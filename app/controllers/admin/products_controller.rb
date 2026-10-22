class Admin::ProductsController < Admin::BaseController
  before_action :set_user

  rescue_from ActiveRecord::RecordInvalid do |exception|
    redirect_to edit_admin_user_path(@user), alert: exception.record.errors.full_messages.to_sentence
  end

  def create
    product = @user.products.create!(product_params)
    product.make_focus! if params.dig(:product, :focus) == "1" || @user.products.one?
    redirect_to edit_admin_user_path(@user), notice: "Product added."
  end

  def update
    product = @user.products.find(params[:id])
    product.update!(product_params)
    product.make_focus! if params.dig(:product, :focus) == "1"
    redirect_to edit_admin_user_path(@user), notice: "Product updated."
  end

  def destroy
    @user.products.find(params[:id]).destroy!
    @user.products.first&.make_focus! unless @user.products.exists?(focus: true)
    redirect_to edit_admin_user_path(@user), notice: "Product deleted."
  end

  private

  def set_user
    @user = User.find(params[:user_id])
  end

  def product_params
    params.require(:product).permit(:name, :url, :stage_problem, :stage_problem_analysis)
  end
end
