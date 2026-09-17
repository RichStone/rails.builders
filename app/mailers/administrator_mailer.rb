class AdministratorMailer < ApplicationMailer
  def enrollment_status(user, status = user.enrollment_status)
    recipients = User.where(administrator: true, notifications_enabled: true, enrollment_notifications: true).pluck(:email)
    return if recipients.empty?

    @user = user
    @status = status
    @url = edit_admin_user_url(user)
    mail(
      to: recipients,
      subject: "Rails Builders: #{user.email} is now #{status.humanize}"
    )
  end
end
