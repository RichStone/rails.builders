require "capybara"
require "selenium-webdriver"

module ChromeStaleNodeErrors
  protected

  def catch_error?(error, errors = nil)
    # Chrome sometimes reports detached DOM nodes as UnknownError during Turbo navigation.
    # Use Capybara's existing stale-element reload and timeout policy for this exact error.
    if error.is_a?(Selenium::WebDriver::Error::UnknownError) &&
        error.message.include?("Node with given id does not belong to the document")
      error = Selenium::WebDriver::Error::StaleElementReferenceError.new(error.message)
    end
    super(error, errors)
  end
end

Capybara::Node::Base.prepend(ChromeStaleNodeErrors)
