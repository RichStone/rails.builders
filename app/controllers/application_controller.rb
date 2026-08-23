class ApplicationController < ActionController::Base
  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  # Changes to the importmap will invalidate the etag for HTML responses
  stale_when_importmap_changes
  after_action :no_store, if: :current_user

  helper_method :current_user, :session_member?, :session_operator?

  private

  def current_user
    @current_user ||= User.find_by(id: session[:user_id])
  end

  def require_user
    redirect_to sign_in_path, alert: "Sign in to continue." unless current_user
  end

  def require_administrator
    return if current_user&.administrator?

    redirect_to(current_user ? dashboard_path : sign_in_path, alert: "Administrator access is required.")
  end

  def require_facilitator
    return if current_user&.facilitator?

    redirect_to(current_user ? dashboard_path : sign_in_path, alert: "Facilitator access is required.")
  end

  def session_member?
    current_user&.active? || current_user&.facilitator? || current_user&.administrator?
  end

  def session_operator?
    current_user&.facilitator? || current_user&.administrator?
  end

  def require_session_member
    return if session_member?

    redirect_to(current_user ? dashboard_path : sign_in_path, alert: "Active Builder access is required.")
  end

  def require_session_operator
    return if session_operator?

    redirect_to(current_user ? builder_sessions_path : sign_in_path, alert: "Facilitator access is required.")
  end
end
