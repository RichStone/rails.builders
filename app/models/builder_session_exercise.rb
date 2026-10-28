class BuilderSessionExercise < ApplicationRecord
  belongs_to :builder_session, touch: true

  validates :builder_session_id, uniqueness: true
  validates :body, presence: true, length: { maximum: 5_000 }
end
