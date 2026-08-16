require "test_helper"

class ProductDigestJobTest < ActiveJob::TestCase
  include ActionMailer::TestHelper

  test "emails each facilitator a summary of products created or updated that day" do
    facilitator = User.create!(email: "facilitator@example.com", facilitator: true)
    builder = User.create!(email: "builder@example.com", name: "Ruby Builder")
    older_product = travel_to(Time.zone.local(2026, 8, 15, 12)) do
      builder.products.create!(name: "Older App", url: "https://older.example")
    end

    travel_to Time.zone.local(2026, 8, 16, 23, 59) do
      older_product.update!(name: "Updated App")
      builder.products.create!(name: "New App", url: "https://new.example")

      assert_emails 1 do
        ProductDigestJob.perform_now(Date.current)
      end
    end

    mail = ActionMailer::Base.deliveries.last
    assert_equal [ facilitator.email ], mail.to
    assert_equal "Rails Builders product updates for 16 August", mail.subject
    assert_match "Created: New App", mail.body.encoded
    assert_match "Updated: Updated App", mail.body.encoded
    assert_match "Ruby Builder", mail.body.encoded
    assert_match "Profile is private", mail.body.encoded
  end

  test "does not email facilitators when no products changed" do
    User.create!(email: "facilitator@example.com", facilitator: true)

    assert_no_emails do
      ProductDigestJob.perform_now(Date.new(2026, 8, 16))
    end
  end
end
