class BuilderSessionChatLogsController < ApplicationController
  before_action :require_session_member
  before_action :require_session_operator
  before_action :set_builder_session

  def create
    save_chat_log
  end

  def update
    save_chat_log
  end

  private

  def set_builder_session
    @builder_session = Program.current.builder_sessions.find(params[:builder_session_id])
  end

  def save_chat_log
    @builder_session.with_lock do
      chat_log = @builder_session.chat_log || @builder_session.build_chat_log
      chat_log.update!(
        content: params.expect(builder_session_chat_log: [ :content ]).require(:content),
        source: "manual",
        imported_at: Time.current
      )
    end
    redirect_to @builder_session, notice: "Meeting chat saved."
  rescue ActiveRecord::RecordInvalid, ActionController::ParameterMissing
    redirect_to @builder_session, alert: "The meeting chat could not be saved."
  end
end
