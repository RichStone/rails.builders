class FacilitatorMailer < ApplicationMailer
  def product_digest(facilitator, product_ids, day)
    @day = day.to_date
    @products = Product.includes(:user).where(id: product_ids).order(:updated_at, :id)
    mail(
      to: facilitator.email,
      subject: "Rails Builders product updates for #{@day.strftime("%-d %B")}"
    )
  end
end
