class FacilitatorMailerPreview < ActionMailer::Preview
  def product_digest
    product = Product.order(updated_at: :desc).first!
    facilitator = User.where(facilitator: true).first!
    day = product.updated_at.to_date

    FacilitatorMailer.product_digest(facilitator, Product.where(updated_at: day.all_day).pluck(:id), day)
  end
end
