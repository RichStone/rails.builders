class AdministratorMailer < ApplicationMailer
  def enrollment_status(user, status = user.enrollment_status)
    @user = user
    @status = status
    mail(
      to: User.where(administrator: true).pluck(:email),
      subject: "Rails Builders: #{user.email} is now #{status}"
    )
  end
end
