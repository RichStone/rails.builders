require "test_helper"

class EnrollmentConcurrencyTest < ActiveSupport::TestCase
  self.use_transactional_tests = false

  setup do
    Product.delete_all
    User.delete_all
    Program.delete_all
    @program = Program.create!(name: "Continuous", starts_on: Date.new(2026, 8, 20), ends_on: Date.new(2026, 12, 17), capacity: 1, og_priority: false)
  end

  teardown do
    Product.delete_all
    User.delete_all
    Program.delete_all
  end

  test "concurrent account deletion submissions are idempotent" do
    user = User.create!(email: "builder@example.com", verified_at: Time.current, enrollment_status: "active", slack_desired_state: "present")
    copies = 2.times.map { User.find(user.id) }
    results = run_concurrently(*copies, &:delete_account!)

    assert_equal 1, results.count(true)
    assert_equal 1, results.count(false)
    assert_not User.exists?(user.id)
    assert_equal 0, @program.reload.occupied_seats
  end

  test "concurrent membership withdrawal releases and promotes exactly once" do
    @program.update!(capacity: 3)
    active = User.create!(email: "active@example.com", verified_at: Time.current, enrollment_status: "active", slack_desired_state: "present")
    first = User.create!(email: "first@example.com", verified_at: Time.current, enrollment_status: "waitlisted", waitlist_joined_at: 2.hours.ago, waitlist_rank: 1)
    second = User.create!(email: "second@example.com", verified_at: Time.current, enrollment_status: "waitlisted", waitlist_joined_at: 1.hour.ago, waitlist_rank: 2)

    results = run_concurrently(User.find(active.id), User.find(active.id)) do |copy|
      copy.update_active_membership!(active: false)
    end

    assert_equal 1, results.count(true)
    assert_equal 1, results.count(false)
    assert_equal "withdrawn", active.reload.enrollment_status
    assert first.reload.offered?
    assert second.reload.waitlisted?
  end

  private

  def run_concurrently(*records)
    ready = Queue.new
    start = Queue.new
    threads = records.map do |record|
      Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          ready << true
          start.pop
          yield record
        end
      end
    end
    records.size.times { ready.pop }
    records.size.times { start << true }
    threads.map(&:value)
  end
end
