class ApplicationController < ActionController::Base
  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  # Changes to the importmap will invalidate the etag for HTML responses
  stale_when_importmap_changes

  helper_method :current_user

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
end
