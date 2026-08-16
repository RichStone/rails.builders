class NewsletterSubscriptionsController < ApplicationController
  def show
    @token = params.require(:token)
    User.find_by_token_for!(:newsletter_confirmation, @token)
  rescue ActionController::ParameterMissing, ActiveSupport::MessageVerifier::InvalidSignature, ActiveRecord::RecordNotFound
    redirect_to root_path, alert: "That newsletter link is invalid or has expired."
  end

  def create
    user = User.find_by_token_for!(:newsletter_confirmation, params.require(:token))
    user.with_lock do
      raise ActiveSupport::MessageVerifier::InvalidSignature unless User.find_by_token_for(:newsletter_confirmation, params[:token]) == user

      user.update!(newsletter_confirmed_at: Time.current, newsletter_token_version: user.newsletter_token_version + 1)
    end
    ClickfunnelsNewsletterJob.perform_later(user.id) if user.verified?
    destination = current_user == user ? dashboard_path : sign_in_path
    redirect_to destination, notice: "Your Loop Labs newsletter subscription is confirmed."
  rescue ActionController::ParameterMissing, ActiveSupport::MessageVerifier::InvalidSignature, ActiveRecord::RecordNotFound
    redirect_to root_path, alert: "That newsletter link is invalid or has expired."
  end
end
