require "test_helper"

class SignupAbuseTest < ActiveSupport::TestCase
  test "counts approved outcomes in hourly buckets without retaining arbitrary data" do
    travel_to Time.utc(2026, 9, 10, 12, 30) do
      assert SignupAbuse.record(:registration_created)
      assert SignupAbuse.record("registration_created")
      assert SignupAbuse.record(:registration_verified)
      assert_not SignupAbuse.record("somebody@example.com")
      assert_not SignupAbuse.record({ email: "somebody@example.com" })

      counts = SignupAbuse.counts
      assert_equal 2, counts.fetch(:registration_created)
      assert_equal 1, counts.fetch(:registration_verified)
      assert_equal 0, counts.fetch(:honeypot)

      travel 24.hours
      assert_equal 0, SignupAbuse.counts.fetch(:registration_created)
    end
  end

  test "spikes notify operations once per hour with no inherited request data" do
    notices = []
    with_stubbed_singleton_method(Honeybadger, :notify, ->(**options) { notices << options }) do
      travel_to Time.utc(2026, 9, 10, 12, 30) do
        19.times { SignupAbuse.record(:registration_created) }
        assert_empty notices
        3.times { SignupAbuse.record(:registration_created) }
        assert_equal 1, notices.size
        notice = Honeybadger::Notice.new(Honeybadger.config, notices.first).as_json
        assert_equal({ reason: "registration_created", count: 20, window: "hour" }, notice.dig(:request, :context))
        assert_equal({}, notice.dig(:request, :params))
        assert_equal({}, notices.first.fetch(:rack_env))
        assert_equal({}, notices.first.fetch(:global_context))
        assert_empty notices.first.fetch(:breadcrumbs)

        travel 1.hour
        20.times { SignupAbuse.record(:registration_created) }
        assert_equal 2, notices.size
      end
    end
  end

  test "monitoring outages cannot break registration" do
    with_stubbed_singleton_method(Rails.cache, :increment, ->(*) { raise IOError, "private detail" }) do
      assert_not SignupAbuse.record(:registration_created)
    end
    with_stubbed_singleton_method(Rails.cache, :read_multi, ->(*) { raise IOError, "private detail" }) do
      assert_nil SignupAbuse.counts
    end
  end

  test "alerts raised while handling a failed request do not inherit its exception" do
    notices = []
    with_stubbed_singleton_method(Honeybadger, :notify, ->(**options) { notices << Honeybadger::Notice.new(Honeybadger.config, options) }) do
      begin
        raise ArgumentError, "private@example.com supplied a private token"
      rescue ArgumentError
        20.times { SignupAbuse.record(:invalid_verification) }
      end
    end

    assert_equal 1, notices.size
    assert_nil notices.first.cause
    assert_empty notices.first.as_json.dig(:error, :causes)
  end
end
