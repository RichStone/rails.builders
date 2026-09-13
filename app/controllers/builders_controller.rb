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
    send_calendar_notification = ActiveModel::Type::Boolean.new.cast(params[:send_calendar_notification])
    if @builder.promote_to_active!(send_calendar_notification:)
      connection = Program.current.calendar_connection
      notice = "Builder promoted to Active Builder."
      notice += " Calendar update queued." if connection&.status == "connected"
      redirect_to builder_path(@builder), notice:
    else
      redirect_to builder_path(@builder), alert: @builder.errors.full_messages.to_sentence
    end
  end

  private

  def set_builder
    @builder = User.find(params[:id])
  end
end
