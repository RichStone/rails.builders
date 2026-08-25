class BuildersController < ApplicationController
  before_action :require_session_operator
  before_action :set_builder, only: %i[show promote]

  def index
    @builders = User.where.not(verified_at: nil).order(:name, :email)
  end

  def show
    @program = Program.current
  end

  def promote
    if @builder.promote_to_active!
      redirect_to builder_path(@builder), notice: "Builder promoted to Active Builder."
    else
      redirect_to builder_path(@builder), alert: @builder.errors.full_messages.to_sentence
    end
  end

  private

  def set_builder
    @builder = User.find(params[:id])
  end
end
