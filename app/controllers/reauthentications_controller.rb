class ReauthenticationsController < ApplicationController
  before_action :no_store
  before_action :require_user
  rate_limit to: 3, within: 15.minutes, by: -> { current_user.id }, only: %i[show create],
    if: -> { action_name == "create" || confirmation_email_due? },
    with: :confirmation_rate_limited
  before_action :set_login_session, only: %i[edit update]

  rescue_from ActionController::ParameterMissing, ActiveSupport::MessageVerifier::InvalidSignature, ActiveRecord::RecordNotFound do
    redirect_to reauthentication_path, alert: "This confirmation link is invalid or expired. Request a new link and open it in the same browser."
  end

  def show
    if current_login_session.recently_authenticated?
      return redirect_to(current_user.administrator? ? admin_root_path : edit_profile_path, notice: "Your email is already confirmed.")
    end

    send_confirmation_email if confirmation_email_due?
    @development_token = session.delete(:development_reauthentication_token) if Rails.env.development?
  end

  def create
    send_confirmation_email
    redirect_to reauthentication_path, notice: "Check your inbox. Open the confirmation link in this browser within 15 minutes."
  end

  def edit
  end

  def update
    context = session[:reauthentication_context]
    @login_session.with_lock do
      raise ActiveRecord::RecordNotFound unless LoginSession.find_by_token_for!(:reauthentication, @token) == @login_session

      start_login_session(@login_session.user)
    end
    if current_user.administrator? && context&.dig("calendar_notes_connection_id") && context.fetch("requested_at", 0) > 15.minutes.ago.to_i
      session[:resume_calendar_notes] = context
      return redirect_to authorize_notes_admin_calendar_connection_path, notice: "Email confirmed. Continue with Google to allow calendar notes access."
    end
    redirect_to(current_user.administrator? ? admin_root_path : edit_profile_path, notice: "Email confirmed. You can now retry your change.")
  end

  private

  def confirmation_email_due?
    !current_login_session.recently_authenticated? && session[:reauthentication_email_sent_at].to_i <= 15.minutes.ago.to_i
  end

  def send_confirmation_email
    token = current_login_session.generate_token_for(:reauthentication)
    UserMailer.reauthentication(current_user, token).deliver_later
    session[:reauthentication_email_sent_at] = Time.current.to_i
    session[:development_reauthentication_token] = token if Rails.env.development?
  end

  def confirmation_rate_limited
    flash.now[:alert] = "Too many confirmation requests. Use the link already in your inbox or try again in 15 minutes."
    render :show, status: :too_many_requests
  end

  def set_login_session
    @token = email_link_token
    @login_session = LoginSession.find_by_token_for!(:reauthentication, @token)
    raise ActiveRecord::RecordNotFound unless @login_session == current_login_session
  end
end
