require "test_helper"

class BuilderSessionMaintenanceJobTest < ActiveJob::TestCase
  setup do
    @facilitator = User.create!(
      email: "facilitator@example.com",
      name: "Facilitator",
      facilitator: true,
      enrollment_status: "active",
      verified_at: Time.current
    )
    @builder = User.create!(
      email: "builder@example.com",
      name: "Builder",
      enrollment_status: "active",
      verified_at: Time.current
    )
    @program = Program.create!(
      name: "Continuous",
      starts_on: Date.new(2026, 8, 20),
      ends_on: Date.new(2026, 12, 17),
      capacity: 9,
      main_facilitator: @facilitator
    )
    @builder_session = @program.builder_sessions.create!(
      assigned_facilitator: @facilitator,
      google_event_id: "calendar-event-1",
      title: "Build together",
      scheduled_starts_at: Time.zone.parse("2026-08-24 18:00"),
      scheduled_ends_at: Time.zone.parse("2026-08-24 18:30"),
      time_zone: "Europe/Madrid"
    )
  end

  test "advances active sessions and automatically finishes them five hours after start" do
    started_at = Time.zone.parse("2026-08-24 18:00")
    travel_to started_at do
      @builder_session.start!(facilitator: @facilitator, duration_seconds: 30.minutes.to_i)
      @builder_session.mark_present!(@builder)
    end

    travel_to started_at + 5.minutes do
      BuilderSessionMaintenanceJob.perform_now

      assert_equal "builder_updates", @builder_session.reload.state
    end

    travel_to started_at + 6.hours do
      BuilderSessionMaintenanceJob.perform_now

      assert_equal "completed", @builder_session.reload.state
      assert_equal "automatic", @builder_session.finish_reason
      assert_equal started_at + 5.hours, @builder_session.ended_at
      assert_equal "pending", @builder_session.transcript.state
    end
  end
end
