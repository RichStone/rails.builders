class BuilderProgressEntriesController < ApplicationController
  before_action :require_session_operator

  def index
    @entries = BuilderProgressEntry.for_program(Program.current).recent_first.includes(:user, :builder_session)
  end

  def update
    builder_session = Program.current.builder_sessions.find(params[:builder_session_id])
    entry = params.expect(progress_entry: %i[user_id body comparison source version])
    entry.require(:user_id)
    raise ActionController::ParameterMissing, :version unless entry.key?(:version)

    builder_session.save_progress_entries!([ entry.to_h.symbolize_keys ])
    redirect_to builder_session_path(builder_session, anchor: "progress"), notice: "Builder progress saved."
  rescue ActiveRecord::RecordInvalid => error
    redirect_to builder_session_path(builder_session, anchor: "progress"), alert: error.record.errors.full_messages.to_sentence
  end
end
