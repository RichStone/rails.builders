require "test_helper"
require_relative "support/chrome_stale_node_errors"

class CapybaraSynchronizationTest < ActiveSupport::TestCase
  setup do
    @session = Capybara::Session.new(:selenium)
    @node = Capybara::Node::Base.new(@session, nil)
    @stale_error = Selenium::WebDriver::Error::UnknownError.new(
      'unknown error: unhandled inspector error: {"code":-32000,"message":"Node with given id does not belong to the document"}'
    )
  end

  test "a detached Chrome node reloads and retries within the existing synchronization" do
    attempts = 0
    reloads = 0
    with_stubbed_singleton_method(@node, :reload, -> { reloads += 1 }) do
      result = @node.synchronize do
        attempts += 1
        raise @stale_error if attempts == 1
        "Mistaken session start discarded."
      end

      assert_equal "Mistaken session start discarded.", result
    end
    assert_equal 2, attempts
    assert_equal 1, reloads
    assert_not @session.synchronized
  end

  test "persistent detached nodes still fail at the configured timeout" do
    error = assert_raises(Selenium::WebDriver::Error::UnknownError) do
      @node.synchronize(0) { raise @stale_error }
    end
    assert_same @stale_error, error
    assert_not @session.synchronized
  end

  test "unrelated errors and explicit retry exclusions fail immediately" do
    [
      [ Selenium::WebDriver::Error::UnknownError.new("browser disconnected"), {} ],
      [ RuntimeError.new(@stale_error.message), {} ],
      [ @stale_error, { errors: [] } ]
    ].each do |original, options|
      attempts = 0
      error = assert_raises(original.class) do
        @node.synchronize(**options) do
          attempts += 1
          raise original
        end
      end
      assert_same original, error
      assert_equal 1, attempts
    end
  end
end
