require "test_helper"

class BuilderSessionExerciseTest < ActiveSupport::TestCase
  setup do
    program = Program.create!(name: "Continuous", starts_on: Date.current, ends_on: 3.months.from_now.to_date)
    @builder_session = program.builder_sessions.create!(
      google_event_id: "exercise-session", title: "Exercise session",
      scheduled_starts_at: 1.hour.from_now, scheduled_ends_at: 2.hours.from_now,
      time_zone: "Europe/Madrid"
    )
  end

  test "each session has at most one nonblank bounded exercise" do
    exercise = @builder_session.build_exercise(body: " ")
    assert_not exercise.valid?
    exercise.body = "a" * 5_001
    assert_not exercise.valid?
    exercise.update!(body: "Describe your product.")

    duplicate = BuilderSessionExercise.new(builder_session: @builder_session, body: "Another exercise.")
    assert_not duplicate.valid?
    assert_includes duplicate.errors[:builder_session_id], "has already been taken"
  end

  test "changing the exercise refreshes the session for connected participants" do
    exercise = @builder_session.create_exercise!(body: "Describe your product.")
    version = @builder_session.reload.updated_at

    travel 1.minute do
      exercise.update!(body: "Describe your customer.")
    end

    assert_operator @builder_session.reload.updated_at, :>, version
    assert_not @builder_session.destroy
    assert exercise.reload.persisted?
  end
end
