class UserMailerPreview < ActionMailer::Preview
  def verification
    UserMailer.verification(preview_user, "preview-verification-token")
  end

  def newsletter_confirmation
    UserMailer.newsletter_confirmation(preview_user, "preview-newsletter-token")
  end

  def seat_offer
    UserMailer.enrollment_status(preview_user, "offered")
  end

  def waitlist
    UserMailer.enrollment_status(preview_user, "waitlisted", 3)
  end

  def confirmed_seat
    UserMailer.enrollment_status(preview_user, "active")
  end

  private

  def preview_user
    User.new(email: "builder@example.com", og: true)
  end
end
