class Product < ApplicationRecord
  STAGE_PROBLEMS = {
    "offer" => "1. Offer",
    "product" => "2. Product",
    "traffic" => "3. Traffic",
    "business_model" => "4. Business Model"
  }.freeze

  belongs_to :user

  encrypts :stage_problem_analysis

  normalizes :name, with: ->(value) { value.strip }
  normalizes :url, with: ->(value) { value.to_s.strip }, apply_to_nil: true
  normalizes :stage_problem, :stage_problem_analysis, with: ->(value) { value.strip.presence }

  validates :name, presence: true
  validates :name, length: { maximum: 120 }
  validates :url, length: { maximum: 2_048 }
  validates :stage_problem, inclusion: { in: STAGE_PROBLEMS.keys }, allow_nil: true
  validates :stage_problem_analysis, length: { maximum: 600 }
  validates :stage_problem, presence: true, if: -> { stage_problem_analysis.present? }
  validate :url_is_an_absolute_web_url, if: -> { url.present? }

  after_save :clear_public_profile_approval, if: -> { saved_change_to_name? || saved_change_to_url? || saved_change_to_focus? }
  after_destroy :clear_public_profile_approval

  def stage_problem_label
    STAGE_PROBLEMS[stage_problem] || "Not assessed yet"
  end

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
