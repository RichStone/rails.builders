require "test_helper"

class LoginSecurityTest < ActionDispatch::IntegrationTest
  setup do
    Program.create!(name: "Continuous", starts_on: Date.new(2026, 8, 20), ends_on: Date.new(2026, 12, 17), capacity: 10)
    @user = User.create!(email: "secure@example.com", verified_at: Time.current, administrator: true)
  end

  test "sign-out revokes copied cookies on the server" do
    sign_in_as(@user)
    copied_cookie = cookies["_rails_builders_session"]

    delete sign_out_path
    cookies["_rails_builders_session"] = copied_cookie
    get dashboard_path

    assert_redirected_to sign_in_path
  end

  test "signing out all devices revokes every login for this user only" do
    sign_in_as(@user)
    first_cookie = cookies["_rails_builders_session"]
    other_device = open_session
    other_device.post verify_email_path, params: { token: @user.reload.generate_token_for(:email_verification) }
    other_cookie = other_device.cookies["_rails_builders_session"]
    other_user = User.create!(email: "unrelated@example.com", verified_at: Time.current)
    unrelated_device = open_session
    unrelated_device.post verify_email_path, params: { token: other_user.generate_token_for(:email_verification) }

    delete sign_out_all_path
    assert_redirected_to root_path
    [ first_cookie, other_cookie ].each do |cookie|
      cookies["_rails_builders_session"] = cookie
      get dashboard_path
      assert_redirected_to sign_in_path
    end
    unrelated_device.get dashboard_path
    assert_equal 200, unrelated_device.response.status
  end

  test "sensitive admin changes require email confirmation and rotate the copied session" do
    builder = User.create!(email: "builder@example.com", verified_at: Time.current)
    sign_in_as(@user)
    copied_cookie = cookies["_rails_builders_session"]
    travel 16.minutes

    get admin_root_path
    assert_response :success
    post grant_administrator_admin_user_path(builder)
    assert_redirected_to reauthentication_path
    assert_not builder.reload.administrator?

    token = request_confirmation_token

    get edit_reauthentication_path(token: token)
    assert_response :success
    post grant_administrator_admin_user_path(builder)
    assert_redirected_to reauthentication_path

    patch reauthentication_path, params: { token: token }
    assert_redirected_to admin_root_path
    patch reauthentication_path, params: { token: token }
    assert_redirected_to reauthentication_path
    post grant_administrator_admin_user_path(builder)
    assert builder.reload.administrator?

    cookies["_rails_builders_session"] = copied_cookie
    get dashboard_path
    assert_redirected_to sign_in_path
  end

  test "confirmation links cannot elevate another login even for the same user" do
    builder = User.create!(email: "builder@example.com", verified_at: Time.current)
    sign_in_as(@user)
    other_device = open_session
    other_device.post verify_email_path, params: { token: @user.reload.generate_token_for(:email_verification) }
    travel 16.minutes
    token = request_confirmation_token

    other_device.patch reauthentication_path, params: { token: token }
    assert_equal reauthentication_path, URI(other_device.response.location).path
    other_device.post grant_administrator_admin_user_path(builder)
    assert_equal reauthentication_path, URI(other_device.response.location).path
    assert_not builder.reload.administrator?
  end

  test "expired and malformed confirmation links do not elevate the session" do
    builder = User.create!(email: "builder@example.com", verified_at: Time.current)
    sign_in_as(@user)
    token = request_confirmation_token
    travel 16.minutes

    [ token, "forged", { invalid: "shape" } ].each do |value|
      patch reauthentication_path, params: { token: value }
      assert_redirected_to reauthentication_path
    end
    post grant_administrator_admin_user_path(builder)
    assert_redirected_to reauthentication_path
    assert_not builder.reload.administrator?
  end

  test "fresh authentication is required for other sensitive entry points" do
    builder = User.create!(email: "builder@example.com", verified_at: Time.current)
    sign_in_as(@user)
    travel 16.minutes

    delete profile_path
    assert_redirected_to reauthentication_path
    assert User.exists?(@user.id)
    delete sign_out_all_path
    assert_redirected_to reauthentication_path
    post promote_builder_path(builder)
    assert_redirected_to reauthentication_path
    assert_not builder.reload.active?
    get callback_admin_calendar_connection_path, params: { code: "unused", state: "unused" }
    assert_redirected_to reauthentication_path
  end

  test "email confirmation requests are rate limited per account" do
    sign_in_as(@user)
    3.times do
      assert_enqueued_emails 1 do
        post reauthentication_path
      end
    end
    assert_no_enqueued_emails do
      post reauthentication_path
    end
    assert_redirected_to reauthentication_path
    assert_match "Too many confirmation requests", flash[:alert]
  end

  test "changing an account email revokes existing sessions and pending sign-in links" do
    builder = User.create!(email: "old@example.com", verified_at: Time.current)
    sign_in_as(builder)
    old_token = builder.reload.generate_token_for(:email_verification)
    admin_device = open_session
    admin_device.post verify_email_path, params: { token: @user.generate_token_for(:email_verification) }

    admin_device.patch admin_user_path(builder), params: { user: { email: "new@example.com" } }
    assert_equal "new@example.com", builder.reload.email
    get dashboard_path
    assert_redirected_to sign_in_path
    post verify_email_path, params: { token: old_token }
    assert_redirected_to sign_in_path
  end

  private

  def sign_in_as(user)
    post verify_email_path, params: { token: user.reload.generate_token_for(:email_verification) }
    assert_redirected_to dashboard_path
  end

  def request_confirmation_token
    perform_enqueued_jobs do
      post reauthentication_path
    end
    mail = ActionMailer::Base.deliveries.last
    assert_equal "Confirm your Rails.Builders identity", mail.subject
    assert_equal [ @user.email ], mail.to
    url = URI.extract(mail.text_part.body.decoded).find { |value| value.include?("/reauthentication/edit") }
    assert_includes mail.html_part.body.decoded, url
    Rack::Utils.parse_query(URI(url).query).fetch("token")
  end
end
