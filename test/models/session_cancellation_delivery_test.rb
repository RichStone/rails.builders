require "test_helper"

class SessionCancellationDeliveryTest < ActiveSupport::TestCase
  setup do
    @user = User.create!(email: "builder@example.com", name: "Casey", verified_at: Time.current, enrollment_status: "active")
    program = Program.create!(name: "Continuous", starts_on: Date.current, ends_on: 3.months.from_now.to_date)
    @session = program.builder_sessions.create!(
      google_event_id: "cancellation-session", title: "Rails.Builders", state: "cancelled",
      scheduled_starts_at: 2.days.from_now, scheduled_ends_at: 2.days.from_now + 90.minutes, time_zone: "Europe/Madrid",
      cancellation_requested_at: Time.current, cancellation_calendar_deleted_at: Time.current,
      cancellation_reason: "The facilitator has an appointment."
    )
    @delivery = @session.cancellation_deliveries.create!(user: @user)
  end

  test "a provider failure retains the first attempt and retries once within the provider window" do
    attempt_time = Time.current.change(usec: 0)
    failing_message = Object.new
    failing_message.define_singleton_method(:deliver_now) { raise IOError, "Provider unavailable" }

    travel_to attempt_time do
      with_stubbed_singleton_method(UserMailer, :session_cancellation, failing_message) do
        assert_raises(IOError) { @delivery.process! }
      end
      assert_equal attempt_time, @delivery.reload.first_attempted_at
      assert_not @delivery.processed?
    end

    travel_to attempt_time + 22.hours do
      assert_difference -> { ActionMailer::Base.deliveries.size }, 1 do
        @delivery.process!
        @delivery.process!
      end
      assert @delivery.reload.sent_at?
      assert_equal attempt_time, @delivery.first_attempted_at
    end
  end

  test "a successful delivery is never sent again even beyond the provider window" do
    assert_difference -> { ActionMailer::Base.deliveries.size }, 1 do
      @delivery.process!
      @delivery.process!
      travel 2.days do
        @delivery.process!
      end
    end
    assert @delivery.reload.sent_at?
    assert @delivery.first_attempted_at?
  end

  test "an uncertain delivery stops automatic retries before the provider key expires" do
    attempted_at = Time.current.change(usec: 0)
    @delivery.update!(first_attempted_at: attempted_at)

    travel_to attempted_at + 23.hours do
      assert @delivery.retry_expired?
      assert_no_difference -> { ActionMailer::Base.deliveries.size } do
        assert_raises(SessionCancellationDelivery::RetryWindowExpired) { @delivery.process! }
      end
    end
    travel_to attempted_at + 2.days do
      assert_no_difference -> { ActionMailer::Base.deliveries.size } do
        assert_raises(SessionCancellationDelivery::RetryWindowExpired) { @delivery.process! }
      end
    end
    assert_equal attempted_at, @delivery.reload.first_attempted_at
    assert_not @delivery.processed?
  end

  test "an opted out recipient is skipped once" do
    @user.update_columns(notifications_enabled: false)

    assert_no_difference -> { ActionMailer::Base.deliveries.size } do
      @delivery.process!
      @delivery.process!
    end

    assert @delivery.reload.skipped_at?
    assert_not @delivery.sent_at?
  end
end
