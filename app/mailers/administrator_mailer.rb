class AdministratorMailer < ApplicationMailer
  def enrollment_status(user, status = user.enrollment_status)
    @user = user
    @status = status
    @url = edit_admin_user_url(user)
    mail(
      to: User.where(administrator: true).pluck(:email),
      subject: "Rails Builders: #{user.email} is now #{status.humanize}"
    )
  end
end
