require "test_helper"

class NotificationPreferencesTest < ActionDispatch::IntegrationTest
  setup do
    @user = User.create!(email: "builder@example.com", verified_at: Time.current, enrollment_status: "active")
  end

  test "builders can configure their own notifications and keep category choices while all are off" do
    post verify_email_path, params: { token: @user.generate_token_for(:email_verification) }
    get notification_preferences_path

    assert_response :success
    assert_select "h1", text: "Configure your notifications"
    assert_select ".form-warning", /🏗️.*Personalized session summaries and trend analysis aren’t fully automated yet, so you can’t opt out of them here./m do
      assert_select "a[href='mailto:rich@looplabs.cc']", text: "rich@looplabs.cc"
    end
    assert_select ".check-row small", /Uncheck to pause the automated notification emails listed below./
    assert_select "input[name='user[notifications_enabled]'][checked]"
    assert_select "input[name='user[enrollment_notifications]'][checked]"
    assert_select "input[name='user[session_reminders]'][checked]"
    assert_select "input[name='user[session_reminder_hours]'][value='36']"
    assert_select "#reminder-timing-help", /Default: 36 hours/
    assert_select "input[name='user[product_update_notifications]']", count: 0

    patch notification_preferences_path, params: { user: {
      notifications_enabled: "0", enrollment_notifications: "0", session_reminders: "1",
      session_reminder_hours: "2", administrator: "1", email: "someone-else@example.com"
    } }

    assert_redirected_to notification_preferences_path
    follow_redirect!
    assert_select ".form-warning a[href='mailto:rich@looplabs.cc']"
    assert_select "input[name='user[notifications_enabled]'][checked]", count: 0
    assert_select "input[name='user[enrollment_notifications]'][checked]", count: 0
    assert_select "input[name='user[session_reminders]'][checked]"
    assert_select "input[name='user[session_reminder_hours]'][value='2']"
    assert_not @user.reload.administrator?
    assert_equal "builder@example.com", @user.email
  end

  test "email links require sign-in and return to preferences without changing them on GET" do
    get notification_preferences_path
    assert_redirected_to sign_in_path
    patch notification_preferences_path, params: { user: { notifications_enabled: "0" } }
    assert_redirected_to sign_in_path
    assert @user.reload.notifications_enabled?

    post verify_email_path, params: { token: @user.generate_token_for(:email_verification) }
    assert_redirected_to notification_preferences_path
    follow_redirect!
    assert_select "input[name='user[notifications_enabled]'][checked]"
    assert_includes response.headers["Cache-Control"], "no-store"
  end

  test "invalid reminder times are rejected without saving any changes" do
    post verify_email_path, params: { token: @user.generate_token_for(:email_verification) }
    [ "0", "169", "1.5", "", "tomorrow" ].each do |hours|
      patch notification_preferences_path, params: { user: { session_reminder_hours: hours, notifications_enabled: "0" } }
      assert_response :unprocessable_content
      assert_select "[role='alert']", /Session reminder hours/
      assert_equal 36, @user.reload.session_reminder_hours
      assert @user.notifications_enabled?
    end
  end

  test "only facilitators see and change their product digest preference" do
    @user.update!(facilitator: true)
    post verify_email_path, params: { token: @user.generate_token_for(:email_verification) }
    get notification_preferences_path
    assert_select "input[name='user[product_update_notifications]'][checked]"

    patch notification_preferences_path, params: { user: { product_update_notifications: "0" } }
    assert_not @user.reload.product_update_notifications?
  end
end
