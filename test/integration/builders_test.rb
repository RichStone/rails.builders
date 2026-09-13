require "test_helper"

class BuildersTest < ActionDispatch::IntegrationTest
  setup do
    @program = Program.create!(
      name: "Continuous",
      starts_on: Date.new(2026, 8, 20),
      ends_on: Date.new(2026, 12, 17),
      capacity: 2
    )
    @admin = User.create!(email: "admin@example.com", verified_at: Time.current, administrator: true)
    @facilitator = User.create!(email: "facilitator@example.com", verified_at: Time.current, facilitator: true)
    @builder = User.create!(
      email: "builder@example.com",
      name: "Waiting Builder",
      verified_at: Time.current,
      enrollment_status: "waitlisted",
      waitlist_rank: 1,
      waitlist_joined_at: Time.current
    )
  end

  test "an Administrator promotes a specific Builder to active from the Builder page" do
    sign_in_as(@admin)

    get builder_path(@builder)
    assert_select "form[action='#{promote_builder_path(@builder)}']", text: "Promote to Active Builder"

    post promote_builder_path(@builder)

    assert_redirected_to builder_path(@builder)
    assert @builder.reload.active?
    assert_nil @builder.waitlist_rank
    assert_nil @builder.waitlist_joined_at
    assert_equal "present", @builder.slack_desired_state
  end

  test "a Facilitator finds and promotes any verified Builder from the Builder page" do
    @program.update!(capacity: 1)
    @builder.update!(enrollment_status: "offered", offer_expires_at: 2.days.from_now, waitlist_rank: nil, waitlist_joined_at: nil)
    sign_in_as(@facilitator)

    get builders_path
    assert_select "a[href='#{builder_path(@builder)}']", text: "Waiting Builder"

    get builder_path(@builder)
    assert_select "form[action='#{promote_builder_path(@builder)}']", text: "Promote to Active Builder"

    post promote_builder_path(@builder)

    assert_redirected_to builder_path(@builder)
    assert @builder.reload.active?
    assert_nil @builder.offer_expires_at
  end

  test "promotion can add the Builder to Google Calendar and send guest notifications" do
    @program.update!(main_facilitator: @facilitator)
    connection = @program.create_calendar_connection!(
      facilitator: @facilitator,
      google_account_email: @facilitator.email,
      google_calendar_id: "sessions@group.calendar.google.com",
      google_calendar_name: "Rails Builders Sessions",
      oauth_token_json: "{}",
      status: "connected"
    )
    sign_in_as(@facilitator)

    get builder_path(@builder)

    assert_select "form[action='#{promote_builder_path(@builder)}']" do
      assert_select "input[name='send_calendar_notification'][type='checkbox']:not([checked])"
      assert_select "small", text: /notify all guests/
    end

    assert_enqueued_with(job: GoogleCalendarAttendeeJob, args: [ connection.id, @builder.id, true ]) do
      post promote_builder_path(@builder), params: { send_calendar_notification: "1" }
    end

    assert_redirected_to builder_path(@builder)
    assert_equal "Builder promoted to Active Builder. Calendar update queued.", flash[:notice]
  end

  test "a regular Builder cannot inspect or promote other Builders" do
    sign_in_as(@builder)

    get builders_path
    assert_redirected_to builder_sessions_path

    post promote_builder_path(@facilitator)
    assert_redirected_to builder_sessions_path
    assert_not @facilitator.reload.active?
  end

  test "promotion is unavailable when every Seat is occupied" do
    @program.update!(capacity: 1)
    User.create!(email: "active@example.com", verified_at: Time.current, enrollment_status: "active")
    sign_in_as(@facilitator)

    get builder_path(@builder)
    assert_select "form[action='#{promote_builder_path(@builder)}']", count: 0
    assert_select ".product-list", text: /No Seat is available/

    post promote_builder_path(@builder)
    assert_redirected_to builder_path(@builder)
    assert @builder.reload.waitlisted?
  end

  private

  def sign_in_as(user)
    token = user.reload.generate_token_for(:email_verification)
    get verify_email_path(token: token)
    post verify_email_path, params: { token: token }
  end
end
