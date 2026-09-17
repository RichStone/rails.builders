require "test_helper"

class FacilitatorMailerTest < ActionMailer::TestCase
  test "facilitators can independently stop enrollment and product updates or pause both" do
    facilitator = User.create!(email: "facilitator@example.com", facilitator: true, enrollment_notifications: false)
    builder = User.create!(email: "builder@example.com")

    assert_no_emails { FacilitatorMailer.enrollment_status(facilitator, builder).deliver_now }
    assert_emails(1) { FacilitatorMailer.product_digest(facilitator, [], Date.current).deliver_now }
    facilitator.update!(enrollment_notifications: true, product_update_notifications: false)
    assert_emails(1) { FacilitatorMailer.enrollment_status(facilitator, builder).deliver_now }
    assert_no_emails { FacilitatorMailer.product_digest(facilitator, [], Date.current).deliver_now }
    facilitator.update!(notifications_enabled: false, product_update_notifications: true)
    assert_no_emails do
      FacilitatorMailer.enrollment_status(facilitator, builder).deliver_now
      FacilitatorMailer.product_digest(facilitator, [], Date.current).deliver_now
    end
  end

  test "product digest delivers product and review actions in both parts" do
    facilitator = User.create!(email: "facilitator@example.com", facilitator: true)
    builder = User.create!(email: "builder@example.com", name: "Ruby Builder")
    product = builder.products.create!(name: "Useful App", url: "https://product.example", focus: true)
    builder.update!(public_profile: true, public_profile_approved: true)
    review_url = Rails.application.routes.url_helpers.facilitator_profile_reviews_url(anchor: "builder-#{builder.id}", host: "example.com")

    mail = FacilitatorMailer.product_digest(facilitator, [ product.id ], Date.new(2026, 8, 16))

    assert_equal [ "facilitator@example.com" ], mail.to
    assert_equal "Rails Builders product updates for 16 August", mail.subject
    assert_equal "multipart/alternative", mail.mime_type
    assert_includes mail.html_part.body.decoded, "Useful App"
    assert_includes mail.text_part.body.decoded, "Useful App"
    assert_includes mail.html_part.body.decoded, "https://product.example"
    assert_includes mail.text_part.body.decoded, "https://product.example"
    assert_includes mail.html_part.body.decoded, review_url
    assert_includes mail.text_part.body.decoded, review_url
  end
end
