require "test_helper"
require "base64"

class ProfileAndPublicPageTest < ActionDispatch::IntegrationTest
  setup do
    @program = Program.create!(name: "Continuous", starts_on: Date.new(2026, 8, 20), ends_on: Date.new(2026, 12, 17), capacity: 10)
    @user = User.create!(email: "builder@example.com", verified_at: Time.current, enrollment_status: "active", og: true)
  end

  test "the public page shows published builders and keeps private OGs anonymous" do
    public_builder = User.create!(email: "public@example.com", name: "Public Builder", og: true)
    public_builder.products.create!(name: "Tiny App", url: "https://example.com", focus: true)
    public_builder.update!(public_profile: true, public_profile_approved: true)

    get root_path

    assert_response :success
    assert_select "h1", /Build in public. Ship with Rails./
    assert_select "#how-it-works"
    assert_select "#active-builders"
    assert_select "#og-builders"
    assert_select ".builder-card", minimum: 2
    assert_includes response.body, "Public Builder"
    assert_not_includes response.body, "builder@example.com"
    assert_includes response.headers.fetch("Content-Security-Policy"), "default-src 'self'"
    assert_equal "no-referrer", response.headers["Referrer-Policy"]
  end

  test "www redirects to the apex before application flows begin" do
    host! "www.rails.builders"

    get "/admin/calendar_connection?from=www"

    assert_response 308
    assert_equal "https://rails.builders/admin/calendar_connection?from=www", response.location
  end

  test "the public page lists only published waitlisted builders in their own group" do
    published_builder = User.create!(email: "waiting-public@example.com", name: "Waiting Builder", og: true,
      verified_at: Time.current, enrollment_status: "waitlisted", waitlist_joined_at: Time.current, waitlist_rank: 1)
    published_builder.products.create!(name: "Queue App", url: "https://queue.example", focus: true)
    published_builder.update!(public_profile: true)
    User.create!(email: "waiting-private@example.com", name: "Hidden Builder", og: true,
      verified_at: Time.current, enrollment_status: "waitlisted", waitlist_joined_at: Time.current, waitlist_rank: 2)

    get root_path

    assert_select "#waitlisted-builders .builder-card", count: 0
    assert_not_includes response.body, "Waiting Builder"

    sign_in_as(published_builder)
    get dashboard_path
    assert_includes response.body, "Waiting for facilitator approval."

    published_builder.update!(public_profile_approved: true)
    get root_path
    assert_select "#waitlisted-builders" do
      assert_select "h3", text: "Waitlisted Builders"
      assert_select ".builder-card", count: 1
      assert_select "h4", text: "Waiting Builder"
    end
    assert_select "#og-builders h4", text: "Waiting Builder", count: 0
    assert_not_includes response.body, "Hidden Builder"

    get dashboard_path
    assert_includes response.body, "Published on the homepage."
  end

  test "public profile text is escaped rather than treated as markup" do
    @user.update!(name: "<script>alert('x')</script>")
    @user.products.create!(name: "<strong>Unsafe</strong>", url: "https://example.com", focus: true)
    @user.update!(testimonial: "<img src=x onerror=alert(1)>", public_profile: true, public_profile_approved: true)

    get root_path

    assert_not_includes response.body, "<script>alert('x')</script>"
    assert_not_includes response.body, "<img src=x onerror=alert(1)>"
    assert_includes response.body, "&lt;script&gt;"
    assert_includes response.body, "&lt;strong&gt;Unsafe&lt;/strong&gt;"
  end

  test "public avatars use a processed image that strips uploaded metadata" do
    @user.update!(name: "Image Builder")
    @user.products.create!(name: "Image App", url: "https://example.com", focus: true)
    @user.avatar.attach(
      io: StringIO.new(Base64.decode64("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=")),
      filename: "avatar.png",
      content_type: "image/png"
    )
    @user.update!(public_profile: true, public_profile_approved: true)

    get root_path

    avatar_url = css_select("img[src*='/rails/active_storage/representations/']").first["src"]
    get avatar_url

    assert_response :redirect
  end

  test "editing a profile clears facilitator approval" do
    @user.products.create!(name: "Approved App", url: "https://approved.example", focus: true)
    @user.update!(name: "Approved Builder", public_profile: true, public_profile_approved: true)
    sign_in_as(@user)

    patch profile_path, params: {
      user: { name: "Edited Builder", testimonial: "New copy", public_profile: "1" }
    }

    assert_redirected_to dashboard_path
    assert @user.reload.public_profile?
    assert_not @user.public_profile_approved?
  end

  test "public profile opt-out does not change enrollment or desired Slack membership" do
    @user.products.create!(name: "Private App", url: "https://private.example", focus: true)
    @user.update!(name: "Private Builder", public_profile: true, public_profile_approved: true)
    sign_in_as(@user)

    patch profile_path, params: { user: { name: "Private Builder", public_profile: "0" } }

    assert_redirected_to dashboard_path
    assert_not @user.reload.public_profile?
    assert @user.active?
    assert_equal "present", @user.slack_desired_state
  end

  test "a signed-in builder can publish a profile with a focus product" do
    sign_in_as(@user)

    get edit_profile_path
    assert_response :success
    assert_select "form.profile-form"

    patch profile_path, params: {
      user: { name: "Ruby Builder", testimonial: "The push I needed.", public_profile: "1" },
      product: { name: "Shipped", url: "https://shipped.example" }
    }

    assert_redirected_to dashboard_path
    assert_equal "Ruby Builder", @user.reload.name
    assert @user.public_profile?
    assert_equal "Shipped", @user.focus_product.name
  end

  test "deleting a profile removes the account and signs out" do
    sign_in_as(@user)

    delete profile_path

    assert_redirected_to root_path
    assert_not User.exists?(@user.id)
    get dashboard_path
    assert_redirected_to sign_in_path
  end

  test "self-service deletion preserves the last verified Administrator" do
    @user.update!(administrator: true)
    sign_in_as(@user)

    delete profile_path

    assert_redirected_to dashboard_path
    assert User.exists?(@user.id)
    assert @user.reload.administrator?

    User.create!(email: "second-admin@example.com", verified_at: Time.current, administrator: true)
    delete profile_path

    assert_redirected_to root_path
    assert_not User.exists?(@user.id)
  end

  test "an incomplete profile cannot be published" do
    sign_in_as(@user)

    patch profile_path, params: { user: { public_profile: "1" } }

    assert_response :unprocessable_content
    assert_not @user.reload.public_profile?
  end

  test "builder can manage multiple products and choose the focus" do
    sign_in_as(@user)
    post products_path, params: { product: { name: "First", url: "https://first.example" } }
    first = @user.products.find_by!(name: "First")
    assert first.focus?

    post products_path, params: { product: { name: "Second", url: "https://second.example" } }
    second = @user.products.find_by!(name: "Second")
    patch product_path(second), params: { product: { name: "Second v2", url: "https://second.example/v2" } }
    patch focus_product_path(second)

    assert_equal "Second v2", second.reload.name
    assert second.focus?
    assert_not first.reload.focus?

    delete product_path(second)
    assert first.reload.focus?
  end

  test "privacy notice identifies the controller, retention, providers, and registrant rights" do
    get privacy_path

    assert_response :success
    assert_select "a[href='mailto:hello@rails.builders']", text: "hello@rails.builders"
    assert_includes response.body, "Rich Steinmetz"
    assert_includes response.body, "30 days"
    assert_includes response.body, "Hetzner"
    assert_includes response.body, "Resend"
    assert_includes response.body, "Honeybadger"
    assert_includes response.body, "ClickFunnels"
    assert_includes response.body, "lodge a complaint"
  end

  private

  def sign_in_as(user)
    token = user.reload.generate_token_for(:email_verification)
    get verify_email_path(token: token)
    post verify_email_path, params: { token: token }
  end
end
