require "test_helper"

class AttendanceTest < ActionDispatch::IntegrationTest
  setup do
    @program = Program.create!(name: "Continuous", starts_on: Date.new(2026, 8, 20), ends_on: Date.new(2026, 12, 17), capacity: 9)
    @builder = User.create!(email: "builder@example.com", name: "Active Builder", enrollment_status: "active", verified_at: Time.current)
    @facilitator = User.create!(email: "facilitator@example.com", name: "Main Facilitator", facilitator: true, enrollment_status: "inactive", verified_at: Time.current)
    @admin = User.create!(email: "admin@example.com", name: "Administrator", administrator: true, enrollment_status: "inactive", verified_at: Time.current)
  end

  test "active Builders Facilitators and Administrators can open Attendance from the menu without caching private data" do
    [ @builder, @facilitator, @admin ].each do |user|
      sign_in_as(user)

      get dashboard_path
      assert_select "nav[aria-label='Main navigation'] a[href='#{attendance_path}']", text: "Attendance"

      get attendance_path
      assert_response :success
      assert_equal "no-store", response.headers["Cache-Control"]
      assert_select "meta[name='turbo-cache-control'][content='no-cache']"

      delete sign_out_path
    end
  end

  test "visitors and Builders without active membership cannot view the cohort or its menu item" do
    completed = create_builder_session("completed", "2026-08-24 18:00")
    record_attendance(completed, @builder, "absent")

    get root_path
    assert_select "a[href='#{attendance_path}']", count: 0
    get attendance_path
    assert_redirected_to sign_in_path
    assert_not_includes response.body, @builder.name

    %w[inactive waitlisted offered withdrawn removed].each do |status|
      user = User.create!(email: "#{status}@example.com", enrollment_status: status, verified_at: Time.current,
        offer_expires_at: (2.days.from_now if status == "offered"))
      sign_in_as(user)

      get dashboard_path
      assert_select "a[href='#{attendance_path}']", count: 0
      get attendance_path
      assert_redirected_to dashboard_path
      assert_not_includes response.body, @builder.name

      delete sign_out_path
    end
  end

  test "the matrix distinguishes recorded absences from missing records and counts only known attendance" do
    present_session = create_builder_session("present", "2026-08-24 18:00")
    absent_session = create_builder_session("absent", "2026-08-31 18:00")
    create_builder_session("unrecorded", "2026-09-07 18:00")
    record_attendance(present_session, @builder, "present")
    record_attendance(absent_session, @builder, "absent")
    sign_in_as(@builder)

    get attendance_path

    assert_response :success
    assert_select ".attendance-matrix tr[data-builder-id='#{@builder.id}']" do
      assert_select ".attendance-mark.is-present", count: 1
      assert_select ".attendance-mark.is-absent", count: 1
      assert_select ".attendance-mark.is-unrecorded", count: 1
      assert_select ".attendance-total", text: /1 missed/
      assert_select ".attendance-total", text: /1\s*\/\s*2 attended/
      assert_select ".attendance-streak", text: "0/3 😊"
    end
    marks = css_select(".attendance-matrix tr[data-builder-id='#{@builder.id}'] .attendance-mark")
    [ [ "24", /attended/i ], [ "31", /missed/i ], [ "07", /no record/i ] ].zip(marks).each do |(day, status), mark|
      assert_includes mark["aria-label"], @builder.name
      assert_match status, mark["aria-label"]
      assert_match /\b#{day}\b/, mark["aria-label"]
      assert_match /2026/, mark["aria-label"]
    end
    assert_select ".attendance-matrix tr[data-builder-id='#{@facilitator.id}']" do
      assert_select ".attendance-mark.is-unrecorded", count: 3
      assert_select ".attendance-total", text: "No record yet"
      assert_select ".attendance-mark.is-absent", count: 0
    end
  end

  test "only completed current-program sessions appear in chronological order" do
    later = create_builder_session("later", "2026-09-07 18:00")
    earlier = create_builder_session("earlier", "2026-08-24 18:00")
    same_time = create_builder_session("same-time", "2026-08-24 18:00")
    %w[ready connection cancelled].each do |state|
      create_builder_session(state, "2026-08-17 18:00", state: state)
    end
    other_program = Program.create!(name: "Other cohort", starts_on: Date.new(2025, 8, 20), ends_on: Date.new(2025, 12, 17), capacity: 9)
    other_session = create_builder_session("other-program", "2025-08-24 18:00", program: other_program)
    former_builder = User.create!(email: "other-cohort@example.com", name: "Other Cohort Builder", enrollment_status: "withdrawn", verified_at: Time.current)
    record_attendance(other_session, former_builder, "absent")
    sign_in_as(@builder)

    get attendance_path

    assert_equal [ earlier, same_time, later ].map { |session| builder_session_path(session) },
      css_select(".attendance-matrix thead a").map { |link| link["href"] }
    assert_select ".attendance-matrix tr[data-builder-id='#{@builder.id}'] .attendance-mark", count: 3
    assert_select ".attendance-matrix tr[data-builder-id='#{former_builder.id}']", count: 0
  end

  test "the roster includes current members and linked history without exposing emails or stitching anonymous snapshots" do
    completed = create_builder_session("completed", "2026-08-24 18:00")
    withdrawn = User.create!(email: "withdrawn@example.com", name: "Former Builder", enrollment_status: "withdrawn", verified_at: Time.current)
    removed_facilitator = User.create!(email: "removed-facilitator@example.com", name: "Removed Facilitator", facilitator: true, enrollment_status: "removed", verified_at: Time.current)
    waiting = User.create!(email: "waiting@example.com", name: "Waiting Builder", enrollment_status: "waitlisted", verified_at: Time.current)
    unnamed = User.create!(email: "private-address@example.com", name: "", enrollment_status: "active", verified_at: Time.current)
    record_attendance(completed, withdrawn, "absent")
    record_attendance(completed, unnamed, "present", display_name: unnamed.email)
    completed.attendances.create!(display_name: @builder.name, role: "builder", status: "absent")
    completed.attendances.create!(display_name: "Unlinked Import Snapshot", role: "builder", status: "absent")
    sign_in_as(@builder)

    get attendance_path

    assert_select ".attendance-matrix tr[data-builder-id='#{withdrawn.id}']", text: /Former Builder/ do
      assert_select ".attendance-mark.is-absent", count: 1
    end
    assert_select ".attendance-matrix tr[data-builder-id='#{@facilitator.id}']", text: /Main Facilitator/
    assert_select ".attendance-matrix tr[data-builder-id='#{removed_facilitator.id}']", count: 0
    assert_select ".attendance-matrix tr[data-builder-id='#{waiting.id}']", count: 0
    assert_select ".attendance-matrix tr[data-builder-id='#{@admin.id}']", count: 0
    assert_select ".attendance-matrix tr[data-builder-id='#{unnamed.id}']", text: /Builder/
    assert_select ".attendance-matrix tr[data-builder-id='#{@builder.id}']" do
      assert_select ".attendance-mark.is-unrecorded", count: 1
      assert_select ".attendance-total", text: "No record yet"
    end
    assert_not_includes response.body, "Unlinked Import Snapshot"
    User.pluck(:email).each { |email| assert_not_includes response.body, email }
  end

  test "an attendance correction updates the matrix and totals on refresh" do
    completed = create_builder_session("completed", "2026-08-24 18:00")
    attendance = record_attendance(completed, @builder, "absent")
    sign_in_as(@builder)

    get attendance_path
    assert_select ".attendance-matrix tr[data-builder-id='#{@builder.id}'] .attendance-total", text: /1 missed/

    attendance.update!(status: "present")
    get attendance_path

    assert_select ".attendance-matrix tr[data-builder-id='#{@builder.id}']" do
      assert_select ".attendance-mark.is-present", count: 1
      assert_select ".attendance-mark.is-absent", count: 0
      assert_select ".attendance-total", text: /0 missed/
      assert_select ".attendance-streak", text: "0/3 😊"
      assert_select ".attendance-total", text: /1\s*\/\s*1 attended/
    end
  end

  test "a cohort without completed sessions has an empty state" do
    create_builder_session("upcoming", "2026-08-24 18:00", state: "ready")
    sign_in_as(@builder)

    get attendance_path

    assert_response :success
    assert_select ".attendance-empty", text: /Attendance will appear here once a completed session has a cohort to show/
    assert_select ".attendance-mark", count: 0
  end

  test "the tally shows the current absence streak and configured limit alongside lifetime totals" do
    sessions = 4.times.map { |index| create_builder_session("streak-#{index}", "2026-09-#{7 + index} 18:00") }
    builders = 5.times.map do |misses|
      user = User.create!(email: "streak#{misses}@example.com", name: "Streak #{misses}", enrollment_status: "active", verified_at: Time.current)
      sessions.each_with_index { |session, index| record_attendance(session, user, index >= 4 - misses ? "absent" : "present") }
      user
    end
    sign_in_as(@builder)

    get attendance_path

    [ "0/3 😊", "1/3 😮", "2/3 🫠", "3/3 ☠️", "4/3 ☠️" ].zip(builders).each do |label, user|
      assert_select "tr[data-builder-id='#{user.id}'] .attendance-streak", text: label
    end
    assert_select "tr[data-builder-id='#{builders.last.id}'] .attendance-total", text: /4 missed/

    @program.update!(consecutive_absence_limit: 4)
    get attendance_path
    assert_select "tr[data-builder-id='#{builders[3].id}'] .attendance-streak", text: "3/4 🫠"
    assert_select "tr[data-builder-id='#{builders[4].id}'] .attendance-streak", text: "4/4 ☠️"
  end

  test "operators can record a separately sent strike email for the current streak and a new streak starts pending" do
    sessions = 3.times.map do |index|
      create_builder_session("strike-#{index}", "2026-09-#{7 + index} 18:00").tap { |session| record_attendance(session, @builder, "absent") }
    end
    latest = sessions.last.attendances.find_by!(user: @builder)
    sign_in_as(@builder)
    get attendance_path
    assert_select "tr[data-builder-id='#{@builder.id}'] .attendance-email", text: "Email Pending"
    assert_select "button", text: "Mark email sent", count: 0
    post mark_strike_email_sent_attendance_path, params: { attendance_id: latest.id }
    assert_redirected_to builder_sessions_path
    assert_nil latest.reload.strike_email_sent_at
    delete sign_out_path

    sign_in_as(@facilitator)
    get attendance_path
    assert_select "button", text: "Mark email sent", count: 1
    post mark_strike_email_sent_attendance_path, params: { attendance_id: latest.id }
    assert_redirected_to attendance_path
    sent_at = latest.reload.strike_email_sent_at
    assert_not_nil sent_at
    follow_redirect!
    assert_select "tr[data-builder-id='#{@builder.id}'] .attendance-email", text: "Email Sent"
    post mark_strike_email_sent_attendance_path, params: { attendance_id: latest.id }
    assert_equal sent_at, latest.reload.strike_email_sent_at

    fourth = create_builder_session("fourth-strike", "2026-09-10 18:00")
    record_attendance(fourth, @builder, "absent")
    get attendance_path
    assert_select "tr[data-builder-id='#{@builder.id}'] .attendance-email", text: "Email Sent"

    returned = create_builder_session("returned", "2026-09-11 18:00")
    record_attendance(returned, @builder, "present")
    get attendance_path
    assert_select "tr[data-builder-id='#{@builder.id}'] .attendance-email", count: 0
    3.times do |index|
      session = create_builder_session("new-strike-#{index}", "2026-09-#{12 + index} 18:00")
      record_attendance(session, @builder, "absent")
    end
    post mark_strike_email_sent_attendance_path, params: { attendance_id: latest.id }
    assert_redirected_to attendance_path
    follow_redirect!
    assert_select "tr[data-builder-id='#{@builder.id}'] .attendance-email", text: "Email Pending"
  end

  test "an email cannot be marked sent below the limit or after an attendance correction" do
    session = create_builder_session("one-miss", "2026-09-07 18:00")
    attendance = record_attendance(session, @builder, "absent")
    sign_in_as(@admin)
    post mark_strike_email_sent_attendance_path, params: { attendance_id: attendance.id }
    assert_nil attendance.reload.strike_email_sent_at

    @program.update!(consecutive_absence_limit: 1)
    attendance.update!(status: "present")
    post mark_strike_email_sent_attendance_path, params: { attendance_id: attendance.id }
    assert_nil attendance.reload.strike_email_sent_at
  end

  private

  def create_builder_session(event_id, starts_at, state: "completed", program: @program)
    starts_at = Time.zone.parse(starts_at)
    program.builder_sessions.create!(
      google_event_id: event_id,
      title: "Session #{event_id}",
      scheduled_starts_at: starts_at,
      scheduled_ends_at: starts_at + 1.hour,
      time_zone: "Europe/Madrid",
      state: state
    )
  end

  def record_attendance(session, user, status, display_name: user.name)
    session.attendances.create!(user: user, display_name: display_name, role: user.facilitator? ? "facilitator" : "builder", status: status)
  end

  def sign_in_as(user)
    token = user.reload.generate_token_for(:email_verification)
    get verify_email_path(token: token)
    post verify_email_path, params: { token: token }
  end
end
