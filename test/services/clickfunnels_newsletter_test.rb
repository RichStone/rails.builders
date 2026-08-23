require "test_helper"

class ClickfunnelsNewsletterTest < ActiveSupport::TestCase
  test "upserts and adds only a missing newsletter tag" do
    user = User.create!(email: "reader@example.com", name: "Ruby Builder")
    service = ClickfunnelsNewsletter.new(user, configuration: configuration)
    requests = []
    response = { "id" => 123, "public_id" => "contact-public-id", "is_active" => true, "tags" => [] }

    service.define_singleton_method(:post) do |path, body|
      requests << [ path, body ]
      requests.one? ? response : {}
    end
    result = service.subscribe!
    assert_equal({ contact_id: "123", contact_public_id: "contact-public-id", status: "subscribed" }, result)

    assert_equal "/workspaces/382270/contacts/upsert", requests.first.first
    assert_equal "reader@example.com", requests.first.last.dig(:contact, :email_address)
    assert_equal "/contacts/contact-public-id/applied_tags", requests.second.first
    assert_equal "123456", requests.second.last.dig(:contacts_applied_tag, :tag_id)
  end

  test "suppressed contacts are flagged without adding a tag" do
    user = User.create!(email: "reader@example.com")
    service = ClickfunnelsNewsletter.new(user, configuration: configuration)
    response = { "id" => 123, "public_id" => "contact-public-id", "is_active" => false, "tags" => [] }

    service.define_singleton_method(:post) { |_path, _body| response }

    assert_equal "blocked_suppressed", service.subscribe!.fetch(:status)
  end

  test "an existing newsletter tag is not applied again" do
    user = User.create!(email: "reader@example.com")
    service = ClickfunnelsNewsletter.new(user, configuration: configuration)
    requests = []
    response = {
      "id" => 123,
      "public_id" => "contact-public-id",
      "is_active" => true,
      "tags" => [ { "id" => 123456, "public_id" => "tag-public-id" } ]
    }

    service.define_singleton_method(:post) do |path, body|
      requests << [ path, body ]
      response
    end

    assert_equal "subscribed", service.subscribe!.fetch(:status)
    assert_equal 1, requests.length
  end

  test "a missing optional public tag id does not match an unrelated tag" do
    user = User.create!(email: "reader@example.com")
    service = ClickfunnelsNewsletter.new(user, configuration: configuration.with(tag_public_id: nil))
    requests = []
    response = {
      "id" => 123,
      "public_id" => "contact-public-id",
      "is_active" => true,
      "tags" => [ { "id" => 999999, "public_id" => nil } ]
    }

    service.define_singleton_method(:post) do |path, body|
      requests << [ path, body ]
      response
    end

    service.subscribe!

    assert_equal 2, requests.length
  end

  private

  def configuration
    ClickfunnelsNewsletter::Configuration.new(
      enabled: true,
      api_token: "test-token",
      base_url: "https://testonly.myclickfunnels.com/api/v2",
      workspace_id: "382270",
      tag_id: "123456",
      tag_public_id: "tag-public-id"
    )
  end
end
