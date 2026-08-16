class Product < ApplicationRecord
  belongs_to :user

  normalizes :name, :url, with: ->(value) { value.strip }

  validates :name, :url, presence: true
  validates :name, length: { maximum: 120 }
  validates :url, length: { maximum: 2_048 }
  validate :url_is_an_absolute_web_url

  def make_focus!
    transaction do
      user.products.where.not(id: id).update_all(focus: false)
      update!(focus: true)
    end
  end

  private

  def url_is_an_absolute_web_url
    uri = URI.parse(url.to_s)
    errors.add(:url, :invalid) unless uri.is_a?(URI::HTTP) && uri.host.present? && uri.userinfo.nil?
  rescue URI::InvalidURIError
    errors.add(:url, :invalid)
  end
end
