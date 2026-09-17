class NotificationPreferencesController < ApplicationController
  before_action :require_notification_user

  def show
  end

  def update
    if current_user.update(notification_params)
      redirect_to notification_preferences_path, notice: "Your notification preferences are saved."
    else
      render :show, status: :unprocessable_content
    end
  end

  private

  def require_notification_user
    session[:return_to_notifications] = true unless current_user
    require_user
  end

  def notification_params
    permitted = %i[notifications_enabled enrollment_notifications session_reminders session_reminder_hours]
    permitted << :product_update_notifications if current_user.facilitator?
    params.require(:user).permit(*permitted)
  end
end
