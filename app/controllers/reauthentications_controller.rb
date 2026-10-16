class ReauthenticationsController < ApplicationController
  before_action :no_store
  before_action :require_user
  rate_limit to: 3, within: 15.minutes, by: -> { current_user.id }, only: :create,
    with: -> { redirect_to reauthentication_path, alert: "Too many confirmation requests. Use the link already in your inbox or try again in 15 minutes." }
  before_action :set_login_session, only: %i[edit update]

  rescue_from ActionController::ParameterMissing, ActiveSupport::MessageVerifier::InvalidSignature, ActiveRecord::RecordNotFound do
    redirect_to reauthentication_path, alert: "This confirmation link is invalid or expired. Request a new link and open it in the same browser."
  end

  def show
    @development_token = session.delete(:development_reauthentication_token) if Rails.env.development?
  end

  def create
    token = current_login_session.generate_token_for(:reauthentication)
    UserMailer.reauthentication(current_user, token).deliver_later
    session[:development_reauthentication_token] = token if Rails.env.development?
    redirect_to reauthentication_path, notice: "Check your inbox. Open the confirmation link in this browser within 15 minutes."
  end

  def edit
  end

  def update
    @login_session.with_lock do
      raise ActiveRecord::RecordNotFound unless LoginSession.find_by_token_for!(:reauthentication, @token) == @login_session

      start_login_session(@login_session.user)
    end
    redirect_to(current_user.administrator? ? admin_root_path : edit_profile_path, notice: "Email confirmed. You can now retry your change.")
  end

  private

  def set_login_session
    @token = email_link_token
    @login_session = LoginSession.find_by_token_for!(:reauthentication, @token)
    raise ActiveRecord::RecordNotFound unless @login_session == current_login_session
  end
end
