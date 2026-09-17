class FacilitatorMailer < ApplicationMailer
  def enrollment_status(facilitator, user, status = user.enrollment_status)
    return unless facilitator.reload.receives_enrollment_notifications?

    @user = user
    @status = status
    mail(
      to: facilitator.email,
      subject: "Rails Builders: #{user.email} is now #{status.humanize}"
    )
  end

  def product_digest(facilitator, product_ids, day)
    return unless facilitator.reload.receives_product_updates?

    @day = day.to_date
    @products = Product.includes(:user).where(id: product_ids).order(:updated_at, :id)
    @url = facilitator_profile_reviews_url
    mail(
      to: facilitator.email,
      subject: "Rails Builders product updates for #{@day.strftime("%-d %B")}"
    )
  end
end
