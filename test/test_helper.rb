ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"

ActionMailer::Base.deliveries.clear

module ActiveSupport
  class TestCase
    # Run tests in parallel with specified workers
    parallelize(workers: :number_of_processors)

    # Setup all fixtures in test/fixtures/*.yml for all tests in alphabetical order.
    fixtures :all

    setup do
      Rails.cache.clear
      BuilderSessionTranscript.delete_all
      BuilderSessionPause.delete_all
      BuilderSessionAttendance.delete_all
      BuilderSession.delete_all
      ProgramCalendarConnection.delete_all
      Product.delete_all
      Program.delete_all
      User.delete_all
    end

    # Add more helper methods to be used by all tests here...
    def with_stubbed_singleton_method(object, method_name, replacement)
      singleton = object.singleton_class
      originally_defined = singleton.instance_methods(false).include?(method_name)
      original = object.method(method_name)
      singleton.define_method(method_name) do |*args, **kwargs, &block|
        replacement.respond_to?(:call) ? replacement.call(*args, **kwargs, &block) : replacement
      end
      yield
    ensure
      if originally_defined
        singleton.define_method(method_name, original)
      else
        singleton.remove_method(method_name)
      end
    end
  end
end
