class BuilderSessionTranscriptsController < ApplicationController
  before_action :require_session_member
  before_action :require_session_operator, only: :create
  before_action :require_administrator, only: :destroy
  before_action :set_builder_session

  def create
    return redirect_to(@builder_session, alert: "A transcript can only be added after the session ends.") unless @builder_session.state == "completed"

    transcript = @builder_session.transcript || @builder_session.create_transcript!
    transcript.replace_with_manual!(transcript_params.fetch(:content))
    redirect_to @builder_session, notice: "Transcript added."
  rescue ActiveRecord::RecordInvalid, ActionController::ParameterMissing
    redirect_to @builder_session, alert: "The transcript could not be added."
  end

  def destroy
    @builder_session.transcript&.delete_content!
    redirect_to @builder_session, notice: "Transcript deleted."
  end

  private

  def set_builder_session
    @builder_session = Program.current.builder_sessions.find(params[:builder_session_id])
  end

  def transcript_params
    params.require(:transcript).permit(:content)
  end
end
