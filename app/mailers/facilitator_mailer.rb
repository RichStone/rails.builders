class FacilitatorMailer < ApplicationMailer
  def enrollment_status(facilitator, user, status = user.enrollment_status)
    return unless facilitator.reload.receives_enrollment_notifications?

    @user = user
    @status = status
    @url = builder_url(user)
    mail(
      to: facilitator.email,
      subject: "Rails.Builders: #{user.email} is now #{status.humanize}"
    )
  end

  def product_digest(facilitator, product_ids, day)
    return unless facilitator.reload.receives_product_updates?

    @day = day.to_date
    @products = Product.includes(:user).where(id: product_ids, users: { public_profile: true, public_profile_approved: false }).order(:updated_at, :id).to_a
    return if @products.empty?

    @url = facilitator_profile_reviews_url
    mail(
      to: facilitator.email,
      subject: "Rails.Builders product updates for #{@day.strftime("%-d %B")}"
    )
  end
end
