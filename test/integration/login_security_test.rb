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
