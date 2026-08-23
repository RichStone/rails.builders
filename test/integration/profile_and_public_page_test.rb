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
    assert_select "h1", /Build in public with other Rails.Builders/
    assert_select "#how-it-works"
    assert_select "#active-builders"
    assert_select "#og-builders"
    assert_select ".builder-card", minimum: 2
    assert_includes response.body, "Public Builder"
    assert_not_includes response.body, "builder@example.com"
    assert_includes response.headers.fetch("Content-Security-Policy"), "default-src 'self'"
    assert_equal "no-referrer", response.headers["Referrer-Policy"]
  end

  test "the public page uses live Program capacity, name, and dates" do
    @program.update!(name: "Continuous r-AI-ls.Builders Edition")

    travel_to Date.new(2026, 8, 23) do
      get root_path
    end

    assert_select ".hero .microcopy", text: /9 places left/
    assert_select ".cohort-strip .eyebrow", text: "Current cohort"
    assert_select ".cohort-strip h2", text: /Continuous r-AI-ls.Builders Edition/
  end

  test "the public page reveals the Program-owned session format" do
    @program.update!(name: "Continuous r-AI-ls.Builders Edition", format_points: "🚂 First stop\n💬 Last stop")

    get root_path

    assert_select "[data-program-format]" do
      assert_select "h2", text: /How the Continuous r-AI-ls.Builders Edition works/
      assert_select "[data-program-format-target='item'][hidden]", count: 2
      assert_select "button[data-action='program-format#start']"
      assert_select "a[href='#{sign_in_path}']", text: "I love it 🤝"
    end
  end

  test "the public page puts the Program-owned readiness checklist after the session format" do
    @program.update!(readiness_points: "Bring one product\nBring one checkout")

    get root_path

    assert_select ".program-format + #readiness.readiness-section" do
      assert_select "h2", text: "Am I ready to join?"
      assert_select "details:not([open]) > summary", text: "?"
      assert_select "input[data-readiness-checklist-target='checkbox']", count: 2
      assert_select ".readiness-smallprint", text: /give Rich a ping/
      assert_select "[data-readiness-checklist-target='unlock'][hidden] a[href='#{sign_in_path}']", text: "Bring me in 🤝"
    end
  end

  test "the public page keeps joining steps and group principles behind reveal controls" do
    get root_path

    assert_select "#how-it-works details.section-reveal:not([open])" do
      assert_select "summary", text: /Crack open the build path/
      assert_select ".steps article", count: 4
    end
    assert_select ".benefits details.section-reveal:not([open])" do
      assert_select "summary", text: /Open the Builders’ code/
      assert_select ".benefit-list article", count: 5
    end
  end

  test "the dashboard displays the Program name everywhere" do
    @program.update!(name: "Continuous r-AI-ls.Builders Edition")
    sign_in_as(@user)

    get dashboard_path

    assert_select ".dashboard-head", text: /Your seat in Continuous r-AI-ls.Builders Edition is confirmed/
    assert_select ".dashboard-grid h2", text: "Continuous r-AI-ls.Builders Edition"
  end

  test "a first visit receives a nonempty CSP nonce shared by every script" do
    get root_path

    csp = response.headers.fetch("Content-Security-Policy")
    nonce = csp.match(/script-src[^;]*'nonce-([^']+)'/)&.captures&.first
    script_nonces = css_select("script[nonce]").map { |script| script["nonce"] }

    assert_predicate nonce, :present?
    assert_predicate script_nonces, :any?
    assert_equal [ nonce ], script_nonces.uniq
    assert_equal nonce, css_select("meta[name='csp-nonce']").first&.[]("content")

    get root_path

    next_nonce = response.headers.fetch("Content-Security-Policy")
      .match(/script-src[^;]*'nonce-([^']+)'/)&.captures&.first
    assert_predicate next_nonce, :present?
    assert_not_equal nonce, next_nonce
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

  test "the profile form shows an existing picture and pauses additional products" do
    @user.avatar.attach(
      io: StringIO.new(Base64.decode64("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=")),
      filename: "avatar.png",
      content_type: "image/png"
    )
    sign_in_as(@user)

    get edit_profile_path

    assert_select ".avatar-preview img", count: 1
    assert_select ".product-list fieldset[disabled]", count: 1
    assert_select ".product-list", text: /focus on one main product/
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
    assert_select "a[href='mailto:rich@looplabs.cc']", text: "rich@looplabs.cc"
    assert_includes response.body, "Rich Steinmetz"
    assert_includes response.body, "30 days"
    assert_includes response.body, "Hetzner"
    assert_includes response.body, "Resend"
    assert_includes response.body, "Honeybadger"
    assert_includes response.body, "ClickFunnels"
    assert_includes response.body, "lodge a complaint"
  end


  test "the footer links to Terms and the source" do
    get root_path
    assert_select "footer a[href='/terms']", text: "Terms"
    assert_select "footer a[href='https://github.com/RichStone/rails.builders']", text: /open source/ do
      assert_select "svg[aria-hidden='true']", count: 1
    end

    get "/terms"
    assert_response :success
    assert_select "h1", text: "Terms of participation"
  end

  private

  def sign_in_as(user)
    token = user.reload.generate_token_for(:email_verification)
    get verify_email_path(token: token)
    post verify_email_path, params: { token: token }
  end
end
