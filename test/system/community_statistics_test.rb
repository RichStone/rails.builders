require "application_system_test_case"

class CommunityStatisticsSystemTest < ApplicationSystemTestCase
  setup do
    Program.create!(name: "Continuous", starts_on: Date.new(2026, 9, 3), ends_on: Date.new(2026, 12, 17))
    CommunityStatistic.current.update!(registrants_count: 21)
  end

  test "all-time counters remain readable on desktop and mobile" do
    visit root_path(anchor: "all-time-builders")
    assert_selector "#all-time-builders dd", text: "21"
    page.save_screenshot(Rails.root.join("tmp/screenshots/community-statistics-desktop.png"))
    page.current_window.resize_to(390, 900)
    assert_selector "#all-time-builders dd", text: "35"
    assert page.evaluate_script("document.documentElement.scrollWidth <= window.innerWidth")
    page.execute_script("document.getElementById('all-time-builders').scrollIntoView({block: 'start', behavior: 'instant'})")
    page.save_screenshot(Rails.root.join("tmp/screenshots/community-statistics-mobile.png"))
  ensure
    page.current_window.resize_to(1280, 900)
  end
end
