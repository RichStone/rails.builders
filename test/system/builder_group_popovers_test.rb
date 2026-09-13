require "application_system_test_case"

class BuilderGroupPopoversTest < ApplicationSystemTestCase
  setup do
    Program.create!(name: "Continuous", starts_on: Date.current, ends_on: 4.months.from_now.to_date, capacity: 12)
    9.times do |index|
      User.create!(email: "builder#{index}@example.com", verified_at: Time.current, enrollment_status: "active", og: true)
    end
  end

  test "builder details appear on desktop hover and in a readable mobile popover" do
    visit root_path

    active_tip = find("#active-builders .builder-info-tip")
    active_tip.scroll_to(:center)
    active_tip.find("summary").hover
    assert_selector "#builder-tip-active-builders", text: "9 Builders meeting weekly to learn from each other", visible: :visible

    page.current_window.resize_to(390, 844)
    visit root_path
    active_tip = find("#active-builders .builder-info-tip")
    active_tip.scroll_to(:center)
    active_tip.find("summary").click

    assert_selector "#active-builders .builder-info-tip[open] summary[aria-expanded='true']"
    popover = find("#builder-tip-active-builders", visible: :visible)
    bounds = page.evaluate_script("""
      ({ left: arguments[0].getBoundingClientRect().left,
         right: arguments[0].getBoundingClientRect().right,
         top: arguments[0].getBoundingClientRect().top,
         bottom: arguments[0].getBoundingClientRect().bottom,
         viewportWidth: window.innerWidth,
         viewportHeight: window.innerHeight })
    """, popover)
    assert_operator bounds.fetch("left"), :>=, 0
    assert_operator bounds.fetch("right"), :<=, bounds.fetch("viewportWidth")
    assert_operator bounds.fetch("top"), :>=, 0
    assert_operator bounds.fetch("bottom"), :<=, bounds.fetch("viewportHeight")

    find("#active-builders .builder-tip-backdrop").click
    assert_no_selector "#active-builders .builder-info-tip[open]"
    assert_selector "#active-builders summary[aria-expanded='false']"
  ensure
    page.current_window.resize_to(1280, 900)
  end
end
