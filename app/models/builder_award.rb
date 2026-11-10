class BuilderAward < ApplicationRecord
  belongs_to :builder_session
  belongs_to :user
  belongs_to :baseline_session, class_name: "BuilderSession", optional: true
  belongs_to :evidence_session, class_name: "BuilderSession", optional: true

  encrypts :citation
  normalizes :title, :citation, with: ->(value) { value.strip }

  validates :title, presence: true, length: { maximum: 100 }
  validates :title, uniqueness: { scope: %i[builder_session_id user_id] }
  validates :citation, presence: true, length: { maximum: 500 }
  validate :eligible_builder, if: :will_save_change_to_user_id?
  validate :earlier_evidence

  scope :revealed, -> { where.not(revealed_at: nil) }
  scope :drafts, -> { where(revealed_at: nil) }

  def self.draft_version(awards)
    awards.map { |award| "#{award.id}:#{award.updated_at.iso8601(6)}" }.join(",")
  end

  private

  def eligible_builder
    errors.add(:user, "must be an Active Builder") unless user&.active? && user.verified?
  end

  def earlier_evidence
    return unless builder_session

    %i[baseline_session evidence_session].each do |field|
      id = public_send("#{field}_id")
      next if id.nil? || builder_session.award_source_sessions.exists?(id:)

      errors.add(field, "must be an earlier completed session in this program with an available record")
    end
  end
end
