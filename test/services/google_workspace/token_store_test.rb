require "test_helper"

class GoogleWorkspace::TokenStoreTest < ActiveSupport::TestCase
  setup do
    facilitator = User.create!(
      email: "otto@looplabs.cc",
      name: "Otto",
      facilitator: true,
      enrollment_status: "active",
      verified_at: Time.current
    )
    program = Program.create!(
      name: "Continuous",
      starts_on: Date.new(2026, 8, 20),
      ends_on: Date.new(2026, 12, 17),
      capacity: 9,
      main_facilitator: facilitator
    )
    @connection = program.create_calendar_connection!(
      facilitator: facilitator,
      google_account_email: facilitator.email,
      google_calendar_id: "pending",
      google_calendar_name: "Pending authorization",
      oauth_token_json: "{}",
      status: "authorizing"
    )
    @store = GoogleWorkspace::TokenStore.new(connection: @connection)
  end

  test "persists tokens in the encrypted connection column" do
    token = '{"refresh_token":"refresh-secret"}'

    @store.store("ignored-user-id", token)

    assert_equal token, @store.load("ignored-user-id")
    assert_not_includes @connection.reload.read_attribute_before_type_cast(:oauth_token_json), "refresh-secret"
  end

  test "treats the empty sentinel as disconnected and clears without deleting the connection" do
    assert_nil @store.load("ignored-user-id")

    @store.store("ignored-user-id", '{"access_token":"temporary"}')
    @store.delete("ignored-user-id")

    assert @connection.reload.persisted?
    assert_equal "{}", @connection.oauth_token_json
    assert_nil @store.load("ignored-user-id")
  end
end
