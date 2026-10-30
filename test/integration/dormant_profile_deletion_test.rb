require "test_helper"

class DormantProfileDeletionTest < ActionDispatch::IntegrationTest
  setup do
    Program.create!(name: "Continuous", starts_on: Date.new(2026, 9, 3), ends_on: Date.new(2026, 12, 17))
  end

  test "successful deletion sends a goodbye that survives the deleted account" do
    user = User.create!(email: "dormant@example.com", verified_at: Time.current, enrollment_status: "inactive", notifications_enabled: false)
    user_id = user.id
    assert_includes User.dormant_without_public_profile, user

    assert_enqueued_emails 1 do
      assert user.delete_account!
    end
    assert_not User.exists?(user_id)
    perform_enqueued_jobs only: UserMailer.delivery_job

    mail = ActionMailer::Base.deliveries.last
    assert_equal [ "dormant@example.com" ], mail.to
    assert_equal "Your Rails.Builders profile has been annihilated 💥", mail.subject
    [ mail.html_part.body.decoded, mail.text_part.body.decoded ].each do |body|
      assert_includes body, "Sign up again"
      assert_includes body, "https://example.com/join"
      assert_not_includes body, "Configure your notifications"
    end
    assert mail.attachments["loop-monster-goodbye.png"].inline?
    assert_equal "cid:loop-monster-goodbye", Nokogiri::HTML(mail.html_part.body.decoded).at_css("img")["src"]
  end

  test "rollback and active account deletion never send the dormant cleanup email" do
    dormant = User.create!(email: "dormant@example.com", verified_at: Time.current, enrollment_status: "inactive")
    assert_no_enqueued_emails do
      User.transaction do
        dormant.destroy!
        raise ActiveRecord::Rollback
      end
    end
    assert User.exists?(dormant.id)
    active = User.create!(email: "active@example.com", verified_at: Time.current, enrollment_status: "active")
    assert_no_enqueued_emails { assert active.delete_account! }
  end

  test "the cleanup list excludes unconfirmed, active, waiting, opted-in profiles and staff" do
    %w[active waitlisted offered removed].each do |status|
      User.create!(email: "#{status}@example.com", verified_at: Time.current, enrollment_status: status)
    end
    User.create!(email: "unconfirmed@example.com", enrollment_status: "inactive")
    User.create!(email: "staff@example.com", administrator: true, verified_at: Time.current, enrollment_status: "inactive")
    User.create!(email: "facilitator@example.com", facilitator: true, verified_at: Time.current, enrollment_status: "inactive")
    pending = User.create!(email: "pending@example.com", name: "Pending profile", verified_at: Time.current, enrollment_status: "inactive")
    pending.products.create!(name: "App", url: "https://example.com", focus: true)
    pending.update!(public_profile: true)
    assert_empty User.dormant_without_public_profile
  end

  test "goodbye delivery does not copy deleted personal details into job logs" do
    output = StringIO.new
    logger = ActiveSupport::Logger.new(output)
    with_stubbed_singleton_method(ActiveJob::Base, :logger, logger) do
      UserMailer.profile_annihilated("private@example.com", "Private Builder", "deleted-account").deliver_later
      perform_enqueued_jobs only: UserMailer.delivery_job
    end

    assert_includes output.string, "Enqueued UserMailDeliveryJob"
    assert_not_includes output.string, "private@example.com"
    assert_not_includes output.string, "Private Builder"
  end
end
