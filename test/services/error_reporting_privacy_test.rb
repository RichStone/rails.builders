require "test_helper"

class ErrorReportingPrivacyTest < ActiveSupport::TestCase
  test "error reports and insights omit caller-controlled request correlation IDs" do
    notices = []
    events = []
    config = Honeybadger.config.dup
    config.configure do |honeybadger|
      honeybadger.api_key = "synthetic-test-key"
      honeybadger.report_data = false
      honeybadger.before_notify { |notice| notices << notice.as_json; notice.halt! }
      honeybadger.before_event { |event| events << event.as_json; event.halt! }
    end
    agent = Honeybadger::Agent.new(config)
    request_id = "synthetic-user@examplecom"

    agent.notify(RuntimeError.new("Synthetic failure"), request_id: request_id)
    agent.event("synthetic_request", request_id: request_id)

    assert_equal 1, notices.size
    assert_equal 1, events.size
    assert_nil notices.first.dig(:correlation_context, :request_id)
    assert_not events.first.key?(:request_id)
  end

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
