class BuilderAwardsController < ApplicationController
  before_action :require_session_operator
  before_action :set_builder_session

  def create
    save_draft(@builder_session.builder_awards.build)
  end

  def update
    save_draft(@builder_session.builder_awards.drafts.find(params[:id]))
  end

  def destroy
    @builder_session.with_lock do
      @builder_session.builder_awards.drafts.find(params[:id]).destroy!
    end
    redirect_to builder_session_path(@builder_session, anchor: "awards"), notice: "Award draft removed."
  end

  def reveal
    destination = builder_session_path(@builder_session, anchor: "awards")
    @builder_session.with_lock do
      unless @builder_session.awards_revealable?
        return redirect_to destination, alert: "Reveal awards at the end of the core session."
      end

      drafts = @builder_session.builder_awards.drafts.order(:id)
      unless params[:version] == BuilderAward.draft_version(drafts)
        return redirect_to destination, alert: "The drafts changed. Review them before revealing."
      end

      now = Time.current
      count = drafts.update_all(revealed_at: now, updated_at: now)
      @builder_session.touch if count.positive?
    end

    redirect_to destination, notice: "Awards revealed to the group."
  end

  private

  def set_builder_session
    @builder_session = Program.current.builder_sessions.find(params[:builder_session_id])
  end

  def save_draft(award)
    @builder_session.with_lock do
      award.reload if award.persisted?
      return head :conflict if award.revealed_at? || @builder_session.state == "cancelled"

      award.update!(params.expect(builder_award: %i[user_id title citation baseline_session_id evidence_session_id]))
    end
    redirect_to builder_session_path(@builder_session, anchor: "awards"), notice: "Award draft saved."
  rescue ActiveRecord::RecordInvalid => error
    redirect_to builder_session_path(@builder_session, anchor: "awards"), alert: error.record.errors.full_messages.to_sentence
  end
end
