require "test_helper"

class AdministratorMailerTest < ActionMailer::TestCase
  test "enrollment update delivers the builder action to every administrator" do
    User.create!(email: "first-admin@example.com", administrator: true)
    User.create!(email: "second-admin@example.com", administrator: true)
    builder = User.create!(email: "builder@example.com", verified_at: Time.current, enrollment_status: "active")
    url = Rails.application.routes.url_helpers.edit_admin_user_url(builder, host: "example.com")

    mail = AdministratorMailer.enrollment_status(builder)

    assert_equal [ "first-admin@example.com", "second-admin@example.com" ], mail.to.sort
    assert_equal "Rails Builders: builder@example.com is now active", mail.subject
    assert_equal "multipart/alternative", mail.mime_type
    assert_includes mail.html_part.body.decoded, "builder@example.com"
    assert_includes mail.text_part.body.decoded, "builder@example.com"
    assert_includes mail.html_part.body.decoded, url
    assert_includes mail.text_part.body.decoded, url
  end
end
