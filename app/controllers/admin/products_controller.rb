class Admin::ProductsController < Admin::BaseController
  before_action :set_user

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
    params.require(:product).permit(:name, :url)
  end
end
