class CleanupStaleRegistrationsJob < ApplicationJob
  queue_as :default

  def perform
    User.where(verified_at: nil, og: false, created_at: ...30.days.ago).find_each(&:destroy!)
  end
end
