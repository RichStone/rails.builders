class FacilitatorMailerPreview < ActionMailer::Preview
  def enrollment_status
    facilitator = User.where(facilitator: true).first!
    builder = User.where(facilitator: false).first || User.first!

    FacilitatorMailer.enrollment_status(facilitator, builder, "offered")
  end

  def product_digest
    product = Product.order(updated_at: :desc).first!
    facilitator = User.where(facilitator: true).first!
    day = product.updated_at.to_date

    FacilitatorMailer.product_digest(facilitator, Product.where(updated_at: day.all_day).pluck(:id), day)
  end
end
