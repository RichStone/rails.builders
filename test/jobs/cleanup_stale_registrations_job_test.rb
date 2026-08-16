require "test_helper"

class CleanupStaleRegistrationsJobTest < ActiveJob::TestCase
  test "deletes only unverified registrations older than thirty days" do
    stale = User.create!(email: "stale@example.com", created_at: 31.days.ago)
    recent = User.create!(email: "recent@example.com", created_at: 29.days.ago)
    verified = User.create!(email: "verified@example.com", created_at: 31.days.ago, verified_at: 30.days.ago)
    og = User.create!(email: "og@example.com", og: true, created_at: 31.days.ago)

    CleanupStaleRegistrationsJob.perform_now

    assert_not User.exists?(stale.id)
    assert User.exists?(recent.id)
    assert User.exists?(verified.id)
    assert User.exists?(og.id)
  end
end
