require "test_helper"
require_relative "support/chrome_stale_node_errors"

class ApplicationSystemTestCase < ActionDispatch::SystemTestCase
  driven_by :selenium, using: :headless_chrome, screen_size: [ 1280, 900 ]
end
