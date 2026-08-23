require "test_helper"

class ProductTest < ActiveSupport::TestCase
  test "a builder can switch focus between multiple products" do
    user = User.create!(email: "builder@example.com")
    first = user.products.create!(name: "First", url: "https://first.example", focus: true)
    second = user.products.create!(name: "Second", url: "https://second.example")

    second.make_focus!

    assert_not first.reload.focus?
    assert second.reload.focus?
    assert_equal second, user.focus_product
  end

  test "product URLs must be web links" do
    product = Product.new(user: User.new(email: "builder@example.com"), name: "Nope", url: "javascript:alert(1)")
    assert_not product.valid?
  end

  test "product input requires bounded text and a URL without embedded credentials" do
    product = Product.new(user: User.new(email: "builder@example.com"), name: "p" * 121, url: "https://user:secret@example.com")

    assert_not product.valid?
    assert product.errors.of_kind?(:name, :too_long)
    assert product.errors.of_kind?(:url, :invalid)
  end

  test "product text input is normalized before validation" do
    product = Product.new(user: User.new(email: "builder@example.com"), name: "  App  ", url: "  https://example.com  ")

    assert product.valid?
    assert_equal "App", product.name
    assert_equal "https://example.com", product.url
  end

  test "product changes clear facilitator approval" do
    user = User.create!(email: "builder@example.com", name: "Builder")
    product = user.products.create!(name: "First", url: "https://first.example", focus: true)
    user.update!(public_profile: true, public_profile_approved: true)

    product.update!(name: "First, improved")

    assert user.reload.public_profile?
    assert_not user.public_profile_approved?

    user.update!(public_profile_approved: true)
    user.products.create!(name: "Second", url: "https://second.example")
    assert_not user.reload.public_profile_approved?
  end
end
