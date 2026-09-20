require "test_helper"

class ErrorReportingPrivacyTest < ActiveSupport::TestCase
  test "error reports omit request headers and login sessions while keeping diagnostic record IDs" do
    environment = Rack::MockRequest.env_for(
      "https://rails.builders/private-request-path",
      "HTTP_COOKIE" => "_rails_builders_session=synthetic-cookie-secret",
      "HTTP_REFERER" => "https://rails.builders/private-referrer-path",
      "rack.session" => { "user_id" => 123, "csrf_token" => "synthetic-session-secret" },
      "action_dispatch.request.parameters" => { "controller" => "builder_sessions", "action" => "show" }
    )
    context = { user_id: 123, builder_session_id: 42 }
    notice = Honeybadger::Notice.new(
      Honeybadger.config,
      exception: RuntimeError.new("Reminder delivery failed"),
      rack_env: environment, context: context, global_context: {}, breadcrumbs: []
    ).as_json

    assert_empty notice.dig(:request, :cgi_data)
    assert_empty notice.dig(:request, :session)
    assert_nil notice.dig(:request, :url)
    assert_equal context, notice.dig(:request, :context)
    assert_equal "RuntimeError", notice.dig(:error, :class)
    assert_includes notice.dig(:error, :message), "Reminder delivery failed"
  end
end
