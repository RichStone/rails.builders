class ProductDigestJob < ApplicationJob
  def perform(day = Time.zone.yesterday)
    day = day.to_date
    product_ids = Product.where(updated_at: day.all_day).pluck(:id)
    return if product_ids.empty?

    User.where(facilitator: true).find_each do |facilitator|
      FacilitatorMailer.product_digest(facilitator, product_ids, day).deliver_now
    end
  end
end
