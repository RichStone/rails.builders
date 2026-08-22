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
    @url = dashboard_url
    @content = enrollment_content
    mail(to: user.email, subject: @content.fetch(:subject))
  end

  def offer_reminder(user)
    @user = user
    return unless user.reload.offered?

    @url = dashboard_url
    mail(to: user.email, subject: "24 hours left to confirm your Rails Builders seat")
  end

  private

  def enrollment_content
    case @status
    when "offered"
      {
        subject: "A Rails Builders seat is yours to confirm",
        preheader: "A Seat is held for you for 72 hours. Confirm or decline it now.",
        eyebrow: "Seat Offer · Action required",
        headline: "A Seat is yours.",
        description: "Confirm your Seat within 72 hours. Rails Builders is holding your place until then. Open your dashboard to accept the Seat Offer. If you decline, Rails Builders can offer it to the next builder.",
        button_label: "Review your Seat Offer",
        note: "Your profile can stay private. You only need to decide whether to take the Seat."
      }
    when "waitlisted"
      {
        subject: "You’re on the Rails Builders waitlist",
        preheader: "You’re ##{@waitlist_position} on the Rails Builders waitlist.",
        eyebrow: "Enrollment update",
        headline: "You’re on the waitlist.",
        description: @user.og? ? "All #{Program.current.capacity} seats are currently reserved. We’ll email you when a Seat becomes available." : "Seats are currently in OG Priority. We’ll contact you when the general waitlist opens and your turn arrives.",
        button_label: "View your waitlist status",
        position: @waitlist_position
      }
    when "active"
      {
        subject: "Your Rails Builders seat is confirmed",
        preheader: "Your Rails Builders Seat is confirmed. You’re officially an Active Builder.",
        eyebrow: "Seat confirmed",
        headline: "You’re in.",
        description: "Your Seat is confirmed. You’re officially an Active Builder.",
        button_label: "Open your dashboard"
      }
    when "declined"
      {
        subject: "You declined your Rails Builders seat",
        preheader: "Your Seat Offer was declined. Rejoining the waitlist is always your choice.",
        eyebrow: "Seat Offer update",
        headline: "Your Seat Offer was declined.",
        description: "We’ve released the Seat. You won’t be added back automatically; you can explicitly join the end of the waitlist from your dashboard.",
        button_label: "Open your dashboard"
      }
    when "expired"
      {
        subject: "Your Rails Builders offer expired",
        preheader: "Your 72-hour Seat Offer expired and the Seat has moved to the next builder.",
        eyebrow: "Seat Offer update",
        headline: "Your Seat Offer expired.",
        description: "The Seat has moved to the next builder. You won’t be added back automatically; you can explicitly join the end of the waitlist from your dashboard.",
        button_label: "Open your dashboard"
      }
    when "withdrawn"
      {
        subject: "Your Rails Builders seat was released",
        preheader: "Your Rails Builders Seat has been released.",
        eyebrow: "Seat update",
        headline: "Your Seat has been released.",
        description: "Your place is open for the next builder. If you want another run, you can explicitly join the end of the waitlist from your dashboard.",
        button_label: "Open your dashboard"
      }
    when "left_waitlist"
      {
        subject: "You left the Rails Builders waitlist",
        preheader: "You are no longer on the Rails Builders waitlist.",
        eyebrow: "Waitlist update",
        headline: "You left the waitlist.",
        description: "You can explicitly join the end of the waitlist again from your dashboard whenever the timing is right.",
        button_label: "Open your dashboard"
      }
    when "removed"
      {
        subject: "Your Rails Builders enrollment was removed",
        preheader: "An Administrator removed your Rails Builders enrollment.",
        eyebrow: "Enrollment update",
        headline: "Your enrollment was removed.",
        description: "An Administrator must reinstate your eligibility before you can join the waitlist again.",
        button_label: "Open your dashboard"
      }
    else
      {
        subject: "Your Rails Builders status changed",
        preheader: "Your Rails Builders enrollment status changed.",
        eyebrow: "Enrollment update",
        headline: "Your enrollment changed.",
        description: "Your current status is #{@status.humanize}.",
        button_label: "Open your dashboard"
      }
    end
  end
end
