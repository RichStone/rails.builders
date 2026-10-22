require "test_helper"

class ProductDigestJobTest < ActiveJob::TestCase
  include ActionMailer::TestHelper

  test "emails only changed products whose public profiles still need approval" do
    facilitator = User.create!(email: "facilitator@example.com", facilitator: true)
    builder = User.create!(email: "builder@example.com", name: "Ruby Builder")
    older_product = travel_to(Time.zone.local(2026, 8, 15, 12)) do
      builder.products.create!(name: "Older App", url: "https://older.example", focus: true)
    end
    builder.update!(public_profile: true)
    unchanged_builder = User.create!(email: "unchanged@example.com", name: "Unchanged Builder")
    travel_to(Time.zone.local(2026, 8, 15, 12)) do
      unchanged_builder.products.create!(name: "Unchanged App", focus: true)
    end
    unchanged_builder.update!(public_profile: true)

    travel_to Time.zone.local(2026, 8, 16, 23, 59) do
      older_product.update!(name: "Updated App")
      builder.products.create!(name: "New App", url: "https://new.example")
      User.create!(email: "private@example.com").products.create!(name: "Private App")
      approved_builder = User.create!(email: "approved@example.com", name: "Approved Builder")
      approved_product = approved_builder.products.create!(name: "Approved App", focus: true)
      approved_builder.update!(public_profile: true, public_profile_approved: true)
      approved_product.update!(stage_problem: "traffic")

      assert_emails 1 do
        ProductDigestJob.perform_now(Date.current)
      end
    end

    mail = ActionMailer::Base.deliveries.last
    assert_equal [ facilitator.email ], mail.to
    assert_equal "Rails.Builders product updates for 16 August", mail.subject
    [ mail.html_part, mail.text_part ].each do |part|
      assert_includes part.body.decoded, "New App"
      assert_includes part.body.decoded, "Updated App"
      assert_includes part.body.decoded, "Ruby Builder"
      assert_includes part.body.decoded, "2 product updates need review"
      assert_not_includes part.body.decoded, "Private App"
      assert_not_includes part.body.decoded, "Approved App"
      assert_not_includes part.body.decoded, "Unchanged App"
    end
  end

  test "does not email facilitators when no products changed" do
    User.create!(email: "facilitator@example.com", facilitator: true)

    assert_no_emails do
      ProductDigestJob.perform_now(Date.new(2026, 8, 16))
    end
  end
end
