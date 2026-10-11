require "application_system_test_case"

class AttendanceSystemTest < ApplicationSystemTestCase
  test "the cohort can scan attendance on desktop and scroll the history on mobile" do
    facilitator = User.create!(name: "Alex Rivera", email: "alex@example.com", facilitator: true, administrator: true, verified_at: Time.current)
    program = Program.create!(name: "Continuous Rails.Builders Edition", starts_on: Date.new(2026, 7, 1), ends_on: Date.new(2026, 12, 17), main_facilitator: facilitator)
    builders = [ "Casey Morgan", "Jamie Chen", "Jordan Bell", "Morgan Ellis", "Robin Patel", "Taylor Verylongfamilyname" ].map.with_index do |name, index|
      User.create!(name: name, email: "builder#{index}@example.com", enrollment_status: "active", verified_at: Time.current)
    end
    sessions = 12.times.map do |index|
      starts_at = Time.zone.local(2026, 7, 16, 16) + index.weeks
      program.builder_sessions.create!(
        title: "Weekly build #{index + 1}", google_event_id: "attendance-browser-#{index}", state: "completed",
        scheduled_starts_at: starts_at, scheduled_ends_at: starts_at + 1.hour, time_zone: "Europe/Madrid",
        started_at: starts_at, ended_at: starts_at + 1.hour, facilitator_name_snapshot: facilitator.name
      ).tap do |builder_session|
        ([ facilitator ] + builders).each_with_index do |builder, position|
          next if position == 6 && index < 5

          builder_session.attendances.create!(user: builder, display_name: builder.name, role: builder.facilitator? ? "facilitator" : "builder", status: (index + position) % 5 == 0 ? "absent" : "present")
        end
      end
    end

    visit verify_email_path(token: facilitator.generate_token_for(:email_verification))
    click_link "Attendance", exact: true

    assert_selector "h1", text: "Attendance"
    assert_selector ".attendance-mark.is-absent"
    assert_selector ".attendance-mark.is-unrecorded"
    assert_selector ".attendance-matrix tbody tr", count: 7
    if ENV["ATTENDANCE_SCREENSHOTS"]
      page.current_window.resize_to(1280, 1500)
      page.save_screenshot(Rails.root.join("tmp/screenshots/attendance-desktop.png"))
    end

    [ 800, 390 ].each do |width|
      page.driver.browser.execute_cdp("Emulation.setDeviceMetricsOverride", width: width, height: 900, deviceScaleFactor: 1, mobile: false)
      page.driver.browser.execute_async_script("const done = arguments[0]; requestAnimationFrame(() => requestAnimationFrame(done));")
      assert_no_horizontal_page_overflow
    end

    region = find(".attendance-scroll")
    region.execute_script("this.scrollIntoView({ block: 'start' })")
    page.save_screenshot(Rails.root.join("tmp/screenshots/attendance-mobile.png")) if ENV["ATTENDANCE_SCREENSHOTS"]
    assert region.evaluate_script("this.scrollWidth > this.clientWidth"), "The session history should scroll within its own region"
    region.execute_script("this.scrollLeft = this.scrollWidth")
    assert region.evaluate_script("this.scrollLeft > 0")
    name_cell = find("tr[data-builder-id='#{facilitator.id}'] .attendance-person")
    assert_operator name_cell.evaluate_script("this.getBoundingClientRect().left"), :>=, 0
    within("tr[data-builder-id='#{facilitator.id}']") do
      assert_text "Alex Rivera"
      find("a[href='#{builder_session_path(sessions.last)}']").click
    end
    assert_current_path builder_session_path(sessions.last)
    assert_selector "h1", text: "Weekly build 12"
  ensure
    page.driver.browser.execute_cdp("Emulation.clearDeviceMetricsOverride")
    page.current_window.resize_to(1280, 900)
  end

  private

  def assert_no_horizontal_page_overflow
    dimensions = page.evaluate_script("[document.documentElement.scrollWidth, window.innerWidth]")
    assert_operator dimensions.first, :<=, dimensions.last, "The page must fit the viewport"
  end
end
