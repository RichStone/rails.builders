class ProductsController < ApplicationController
  before_action :require_user

  rescue_from ActiveRecord::RecordInvalid do |exception|
    redirect_to edit_profile_path, alert: exception.record.errors.full_messages.to_sentence
  end

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

  def stage
    product = session_operator? ? Product.find(params[:id]) : current_user.products.find(params[:id])
    destination = session_operator? && product.user != current_user ? builder_path(product.user) : edit_profile_path

    if product.update(params.require(:product).permit(:stage_problem, :stage_problem_analysis))
      redirect_to destination, notice: "Product stage updated."
    else
      redirect_to destination, alert: product.errors.full_messages.to_sentence
    end
  end

  private

  def product_params
    params.require(:product).permit(:name, :url, :stage_problem, :stage_problem_analysis)
  end
end
