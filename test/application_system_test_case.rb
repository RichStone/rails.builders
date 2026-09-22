require "test_helper"
require_relative "support/chrome_stale_node_errors"

class ApplicationSystemTestCase < ActionDispatch::SystemTestCase
  driven_by :selenium, using: :headless_chrome, screen_size: [ 1280, 900 ] do |options|
    # Exercise the app's reduced-motion CSS: scrolling/entrance animations must
    # not move controls between WebDriver locating them and delivering a click.
    options.add_argument("--force-prefers-reduced-motion")
  end

  private

  def click_button_and_wait_for_navigation(label)
    # An old success flash (or an edited input) does not prove this save finished.
    # Both Turbo body replacement and native navigation remove this marker.
    page.execute_script("document.body.setAttribute('data-test-navigation-pending', '')")
    click_button label
    assert_no_selector "body[data-test-navigation-pending]", visible: :all
  end
end
