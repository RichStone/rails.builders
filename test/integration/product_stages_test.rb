require "test_helper"

class ProductStagesTest < ActionDispatch::IntegrationTest
  setup do
    @builder = User.create!(email: "builder@example.com", name: "Builder", verified_at: Time.current, enrollment_status: "active")
    @facilitator = User.create!(email: "facilitator@example.com", name: "Facilitator", verified_at: Time.current, facilitator: true)
    @admin = User.create!(email: "admin@example.com", verified_at: Time.current, administrator: true)
    @product = @builder.products.create!(name: "Useful App", url: "https://example.com", focus: true)
    @program = Program.create!(name: "Continuous", starts_on: Date.current, ends_on: 4.months.from_now.to_date, main_facilitator: @facilitator)
  end

  test "builder saves the focus product assessment from Profile and sees it on their dashboard" do
    @builder.update!(public_profile: true, public_profile_approved: true)
    sign_in_as(@builder)

    get edit_profile_path
    assert_select "form.profile-form select[name='product[stage_problem]'] option", text: "1. Offer"
    assert_select "details.stage-guide", text: /Clarify who buys, the outcome they want, and how you present and price the offer/

    patch profile_path, params: {
      user: { name: "Builder" },
      product: { name: "Useful App", url: "https://example.com", stage_problem: "offer", stage_problem_analysis: "The app works, but sustained demand is not proven." }
    }

    assert_redirected_to dashboard_path
    follow_redirect!
    assert_select "[data-current-problem] [data-product-stage]", text: /1. Offer.*sustained demand is not proven/m
    assert_equal "offer", @product.reload.stage_problem
    assert @builder.reload.public_profile_approved?
  end

  test "product creation and ordinary edits accept the stage fields" do
    sign_in_as(@builder)
    post products_path, params: { product: { name: "Second App", url: "https://second.example", stage_problem: "product", stage_problem_analysis: "Paying customers need more reliable exports." } }
    product = @builder.products.find_by!(name: "Second App")
    assert_equal "product", product.stage_problem

    patch product_path(product), params: { product: { stage_problem: "traffic", stage_problem_analysis: "Retention is proven; qualified acquisition is the bottleneck." } }
    assert_redirected_to edit_profile_path
    assert_equal "traffic", product.reload.stage_problem
  end

  test "an offer-stage product can be named and assessed before it has a website" do
    sign_in_as(@builder)
    post products_path, params: { product: { name: "New offer", stage_problem: "offer", stage_problem_analysis: "Test whether the proposed outcome is worth paying for." } }
    assert_redirected_to edit_profile_path
    product = @builder.products.find_by!(name: "New offer")
    assert_equal "", product.url
    product.make_focus!
    @builder.update!(public_profile: true, public_profile_approved: true)
    @facilitator.products.create!(name: "New workshop", focus: true)
    @facilitator.update!(public_profile: true, public_profile_approved: true)

    get root_path
    assert_select ".builder-card", text: /New offer/
    assert_select ".builder-card a", text: "New offer", count: 0
    assert_select ".facilitator", text: /Working on New workshop/
    assert_select ".facilitator a", text: "New workshop", count: 0

    session = @program.builder_sessions.create!(google_event_id: "prelaunch", title: "Weekly Builders", scheduled_starts_at: Time.current, scheduled_ends_at: 1.hour.from_now, time_zone: "Europe/Madrid")
    session.start!(facilitator: @facilitator)
    session.finish_current_speaker! until session.current_speaker_attendance.user == @builder
    get builder_session_path(session)
    assert_select "[data-speaker-project] strong", text: "New offer"
    assert_select "[data-speaker-project] a", count: 0
    assert_select ".live-session-stage [data-product-stage]", text: /1. Offer/
  end

  test "facilitators and administrators update another builder's assessment without editing public product fields" do
    [ @facilitator, @admin ].each do |operator|
      sign_in_as(operator)
      get builder_path(@builder)
      assert_select "form[action='#{stage_product_path(@product)}'] select[name='product[stage_problem]']"

      patch stage_product_path(@product), params: { product: { name: "Unwanted rename", user_id: operator.id, stage_problem: "business_model", stage_problem_analysis: "Growth has stalled despite a validated offer and working acquisition." } }

      assert_redirected_to builder_path(@builder)
      assert_equal "business_model", @product.reload.stage_problem
      assert_equal "Useful App", @product.name
      assert_equal @builder, @product.user
    end
  end

  test "administrators can set stages in their existing product forms" do
    sign_in_as(@admin)
    get edit_admin_user_path(@builder)
    assert_select "[data-admin-products] select[name='product[stage_problem]']"
    assert_select "[data-admin-add-product] textarea[name='product[stage_problem_analysis]']"

    patch admin_user_product_path(@builder, @product), params: { product: { stage_problem: "product", stage_problem_analysis: "Validated customers need a shorter activation flow." } }
    assert_redirected_to edit_admin_user_path(@builder)
    assert_equal "product", @product.reload.stage_problem

    post admin_user_products_path(@builder), params: { product: { name: "New App", url: "https://new.example", stage_problem: "offer" } }
    assert_equal "offer", @builder.products.find_by!(name: "New App").stage_problem
  end

  test "other builders and signed-out visitors cannot change an assessment" do
    peer = User.create!(email: "peer@example.com", verified_at: Time.current, enrollment_status: "active")
    sign_in_as(peer)
    patch stage_product_path(@product), params: { product: { stage_problem: "traffic" } }
    assert_response :not_found
    patch product_path(@product), params: { product: { stage_problem: "traffic" } }
    assert_response :not_found
    assert_nil @product.reload.stage_problem

    delete sign_out_path
    patch stage_product_path(@product), params: { product: { stage_problem: "traffic" } }
    assert_redirected_to sign_in_path
    assert_nil @product.reload.stage_problem
  end

  test "invalid assessments are rejected without overwriting the saved assessment" do
    @product.update!(stage_problem: "offer", stage_problem_analysis: "Demand needs validation.")
    sign_in_as(@builder)

    [ { stage_problem: "unknown" }, { stage_problem: "traffic", stage_problem_analysis: "x" * 601 }, { stage_problem: "" } ].each do |attributes|
      patch stage_product_path(@product), params: { product: attributes }
      assert_redirected_to edit_profile_path
      assert flash[:alert].present?
      assert_equal "offer", @product.reload.stage_problem
      assert_equal "Demand needs validation.", @product.stage_problem_analysis
    end

    patch product_path(@product), params: { product: { stage_problem: "unknown" } }
    assert_redirected_to edit_profile_path
    assert_equal "offer", @product.reload.stage_problem

    patch stage_product_path(@product), params: { product: { stage_problem: "", stage_problem_analysis: "" } }
    assert_nil @product.reload.stage_problem
    assert_nil @product.stage_problem_analysis
  end

  test "assessments appear in private ready and live sessions but stay off approved public profiles" do
    @product.update!(stage_problem: "offer", stage_problem_analysis: "<script>privateDemand()</script> No repeat customers yet.")
    @builder.update!(public_profile: true, public_profile_approved: true)
    session = @program.builder_sessions.create!(google_event_id: "stages", title: "Weekly Builders", scheduled_starts_at: Time.current, scheduled_ends_at: 1.hour.from_now, time_zone: "Europe/Madrid")
    sign_in_as(@builder)

    get builder_session_path(session)
    assert_select "[data-product-stage]", text: /No repeat customers yet/
    assert_select "[data-product-stage] script", count: 0

    session.start!(facilitator: @facilitator)
    session.finish_current_speaker! until session.current_speaker_attendance.user == @builder
    get builder_session_path(session)
    assert_select ".live-session-stage [data-product-stage]", text: /1. Offer/

    delete sign_out_path
    get root_path
    assert_select "[data-product-stage]", count: 0
    assert_not_includes response.body, "privateDemand"
    get builder_session_path(session)
    assert_redirected_to sign_in_path
  end

  private

  def sign_in_as(user)
    token = user.reload.generate_token_for(:email_verification)
    get verify_email_path(token: token)
    post verify_email_path, params: { token: token }
  end
end
