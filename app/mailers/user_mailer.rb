class UserMailer < ApplicationMailer
  def verification(user, token)
    @user = user
    @url = verify_email_url(token: token)
    mail(to: user.email, subject: "Your Rails Builders sign-in link")
  end

  def newsletter_confirmation(user, token)
    @user = user
    @url = confirm_newsletter_url(token: token)
    mail(to: user.email, subject: "Confirm the Loop Labs newsletter")
  end

  def enrollment_status(user, status = user.enrollment_status, waitlist_position = user.waitlist_position)
    @user = user
    @status = status
    @waitlist_position = waitlist_position
    mail(to: user.email, subject: enrollment_subject)
  end

  def offer_reminder(user)
    @user = user
    return unless user.reload.offered?

    mail(to: user.email, subject: "24 hours left to confirm your Rails Builders seat")
  end

  private

  def enrollment_subject
    {
      "waitlisted" => "You’re on the Rails Builders waitlist",
      "offered" => "A Rails Builders seat is yours to confirm",
      "active" => "Your Rails Builders seat is confirmed",
      "declined" => "You declined your Rails Builders seat",
      "expired" => "Your Rails Builders offer expired",
      "withdrawn" => "Your Rails Builders seat was released"
    }.fetch(@status, "Your Rails Builders status changed")
  end
end
