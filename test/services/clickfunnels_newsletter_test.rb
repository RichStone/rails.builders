require "test_helper"

class ClickfunnelsNewsletterTest < ActiveSupport::TestCase
  test "upserts and adds only a missing newsletter tag" do
    user = User.create!(email: "reader@example.com", name: "Ruby Builder")
    service = ClickfunnelsNewsletter.new(user)
    requests = []
    response = { "id" => 123, "public_id" => "contact-public-id", "is_active" => true, "tags" => [] }

    service.define_singleton_method(:post) do |path, body|
      requests << [ path, body ]
      requests.one? ? response : {}
    end
    result = service.subscribe!
    assert_equal({ contact_id: "123", contact_public_id: "contact-public-id", status: "subscribed" }, result)

    assert_equal "/workspaces/477369/contacts/upsert", requests.first.first
    assert_equal "reader@example.com", requests.first.last.dig(:contact, :email_address)
    assert_equal "/contacts/contact-public-id/applied_tags", requests.second.first
    assert_equal "448334", requests.second.last.dig(:contacts_applied_tag, :tag_id)
  end

  test "suppressed contacts are flagged without adding a tag" do
    user = User.create!(email: "reader@example.com")
    service = ClickfunnelsNewsletter.new(user)
    response = { "id" => 123, "public_id" => "contact-public-id", "is_active" => false, "tags" => [] }

    service.define_singleton_method(:post) { |_path, _body| response }

    assert_equal "blocked_suppressed", service.subscribe!.fetch(:status)
  end
end
