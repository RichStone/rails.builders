class ProductsController < ApplicationController
  before_action :require_user

  def create
    product = current_user.products.create!(product_params)
    product.make_focus! if current_user.products.count == 1
    redirect_to edit_profile_path, notice: "Product added."
  end

  def update
    current_user.products.find(params[:id]).update!(product_params)
    redirect_to edit_profile_path, notice: "Product updated."
  end

  def destroy
    product = current_user.products.find(params[:id])
    was_focus = product.focus?
    product.destroy!
    current_user.products.first&.make_focus! if was_focus
    redirect_to edit_profile_path, notice: "Product removed."
  end

  def focus
    current_user.products.find(params[:id]).make_focus!
    redirect_to edit_profile_path, notice: "Focus product updated."
  end

  private

  def product_params
    params.require(:product).permit(:name, :url)
  end
end
