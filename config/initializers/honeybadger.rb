# Rails request IDs can come from client headers, so omit them from telemetry.
Honeybadger.configure do |config|
  config.before_notify { |notice| notice.request_id = nil }
  config.before_event { |event| event.delete(:request_id) }
end
