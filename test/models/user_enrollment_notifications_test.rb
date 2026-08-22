require "test_helper"

class UserEnrollmentNotificationsTest < ActiveJob::TestCase
  include ActionMailer::TestHelper

  setup do
    Program.create!(
      name: "Continuous",
      starts_on: Date.new(2026, 8, 20),
      ends_on: Date.new(2026, 12, 17),
      capacity: 9,
      og_priority: true
    )
  end

  test "waitlist, Seat Offer, and Active Builder transitions email every facilitator once" do
    facilitator = User.create!(email: "facilitator@example.com", facilitator: true)
    dual_role = User.create!(email: "dual-role@example.com", facilitator: true, administrator: true)
    administrator = User.create!(email: "administrator@example.com", administrator: true)
    builder = User.create!(email: "builder@example.com")
    clear_enqueued_jobs
    ActionMailer::Base.deliveries.clear

    perform_enqueued_jobs do
      builder.complete_verification!
      builder.issue_offer!
      builder.accept_offer!
    end

    operational_mail = ActionMailer::Base.deliveries.select { |mail| mail.subject.start_with?("Rails Builders:") }
    recipient_counts = operational_mail.flat_map(&:to).tally
    facilitator_mail = operational_mail.select { |mail| mail.to == [ facilitator.email ] }

    assert_equal 3, recipient_counts[facilitator.email]
    assert_equal 3, recipient_counts[dual_role.email]
    assert_equal 3, recipient_counts[administrator.email]
    assert_equal [
      "Rails Builders: builder@example.com is now Active",
      "Rails Builders: builder@example.com is now Offered",
      "Rails Builders: builder@example.com is now Waitlisted"
    ], facilitator_mail.map(&:subject).sort
    assert facilitator_mail.all?(&:multipart?)
    assert facilitator_mail.all? { |mail| mail.html_part.body.decoded.include?(builder.email) }
    assert facilitator_mail.all? { |mail| mail.text_part.body.decoded.include?(builder.email) }
  end
end
