class AdministratorMailerPreview < ActionMailer::Preview
  def enrollment_status
    builder = User.where(administrator: false).first || User.first!
    builder.email = "builder@example.com"

    AdministratorMailer.enrollment_status(builder, "offered")
  end
end
