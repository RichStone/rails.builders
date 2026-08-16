class Facilitator::ProfileReviewsController < ApplicationController
  before_action :require_facilitator

  def index
    @builders = User.where(public_profile: true).includes(:products).order(:name, :email)
  end

  def update
    builder = User.where(public_profile: true).find(params[:id])
    approved = ActiveModel::Type::Boolean.new.cast(params.require(:user).fetch(:public_profile_approved))

    if builder.update(public_profile_approved: approved)
      notice = approved ? "Profile approved for publication." : "Profile removed from publication."
      redirect_to facilitator_profile_reviews_path(anchor: "builder-#{builder.id}"), notice: notice
    else
      redirect_to facilitator_profile_reviews_path(anchor: "builder-#{builder.id}"), alert: builder.errors.full_messages.to_sentence
    end
  end
end
