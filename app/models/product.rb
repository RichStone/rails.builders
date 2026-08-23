class Product < ApplicationRecord
  belongs_to :user

  normalizes :name, :url, with: ->(value) { value.strip }

  validates :name, :url, presence: true
  validates :name, length: { maximum: 120 }
  validates :url, length: { maximum: 2_048 }
  validate :url_is_an_absolute_web_url

  after_save :clear_public_profile_approval
  after_destroy :clear_public_profile_approval

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

  def clear_public_profile_approval
    User.where(id: user_id, public_profile_approved: true).update_all(public_profile_approved: false)
  end
end
