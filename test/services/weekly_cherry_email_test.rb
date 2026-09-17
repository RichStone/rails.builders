require "test_helper"

class WeeklyCherryEmailTest < ActiveSupport::TestCase
  setup do
    @facilitator = User.create!(email: "rich@example.com", name: "Rich", facilitator: true, verified_at: Time.current)
    @builder = User.create!(email: "builder@example.com", name: "Builder", enrollment_status: "active", verified_at: Time.current)
    @absentee = User.create!(email: "absent@example.com", name: "Absent", enrollment_status: "active", verified_at: Time.current)
    @program = Program.create!(name: "Builders", starts_on: Date.current, ends_on: 3.months.from_now.to_date, main_facilitator: @facilitator)
    @session = @program.builder_sessions.create!(google_event_id: "cherry", title: "Offers", scheduled_starts_at: 2.days.ago, scheduled_ends_at: 2.days.ago + 1.hour, time_zone: "Europe/Berlin", state: "completed", assigned_facilitator: @facilitator)
    @session.create_transcript!(state: "ready", source: "manual", content: "Private transcript")
    @session.attendances.create!(user: @builder, display_name: "Builder", role: "builder", status: "present")
    @session.attendances.create!(user: @facilitator, display_name: "Rich", role: "facilitator", status: "present")
    @session.attendances.create!(user: @absentee, display_name: "Absent", role: "builder", status: "absent")
    @next_session = @program.builder_sessions.create!(google_event_id: "next-cherry", title: "Next week", scheduled_starts_at: 5.days.from_now, scheduled_ends_at: 5.days.from_now + 1.hour, time_zone: "Europe/Berlin")
  end

  test "recipients include active members and the facilitator exactly once" do
    assert_equal [ @facilitator.id, @builder.id, @absentee.id ].sort, WeeklyCherryEmail.recipients_for(@session).map(&:id).sort
    @facilitator.update!(enrollment_status: "active")
    assert_equal 3, WeeklyCherryEmail.recipients_for(@session).length
  end

  test "renders attendee promise and only feedback received without sending mail" do
    @session.next_session_promises.create!(user: @builder, body: "Speak to five customers.")
    @session.peer_feedbacks.create!(author: @facilitator, recipient: @builder, body: "Show the price before the call.", sentiment: "idea", source: "transcript", source_key: "price")
    @session.peer_feedbacks.create!(author: @builder, recipient: @facilitator, body: "Private to Rich's version.", sentiment: "encouraging", source: "transcript", source_key: "rich")

    assert_no_difference "ActionMailer::Base.deliveries.size" do
      email = render_for(@builder)
      assert_equal @builder.email, email.fetch(:to)
      assert_includes email.fetch(:text), "You promised to speak to five customers"
      assert_includes email.fetch(:html), "Show the price before the call."
      assert_not_includes email.fetch(:html), "Private to Rich"
      assert_includes email.fetch(:html), "cid:weekly-cherry"
      assert_includes email.fetch(:html), "#ffe6ed"
      assert_includes email.fetch(:text), "https://rails.builders/sessions/#{@session.id}"
      assert_includes email.fetch(:text), "Europe/Berlin"
      assert_includes email.fetch(:text), "Rich and Otto Labot"
      assert_includes email.fetch(:html), "Rich and Otto Labot"
      assert_not_includes email.fetch(:html), "Private transcript"
    end
  end

  test "absentees get the missed subject count and next meeting without an invented promise" do
    @next_session.update!(meet_url: "https://meet.google.com/abc-defg-hij")
    email = render_for(@absentee)
    assert_equal "You missed Sharper offers, five customers, ship the page", email.fetch(:subject)
    assert_includes email.fetch(:text), "1st missed session in a row"
    assert_includes email.fetch(:text), "Two more"
    assert_includes email.fetch(:text), "The Builders didn't mention you this time."
    assert_includes email.fetch(:text), "https://meet.google.com/abc-defg-hij"
    assert_not_includes email.fetch(:text), "TL;DR"
    assert_not_includes email.fetch(:text), "You promised"
    assert_not_includes email.fetch(:html), "Your promise"
  end

  test "email openings skip the decorative headline and attendee review links use the requested label" do
    [ @builder, @absentee ].each do |recipient|
      email = render_for(recipient)
      html = Nokogiri::HTML.fragment(email.fetch(:html))
      assert_empty html.css("h1")
      assert_not_includes email.fetch(:text), "A little momentum"
      assert_includes html.text, "Hey #{recipient.name},"

      link = html.at_css("a[href='https://rails.builders/sessions/#{@session.id}']")
      if recipient == @builder
        assert_equal "Review the last session ->", link.text
        assert_includes email.fetch(:text), "Review the last session -> https://rails.builders/sessions/#{@session.id}"
      else
        assert_nil link
      end
    end
  end

  test "consecutive absences reset on attendance and ignore cancelled sessions" do
    older = @program.builder_sessions.create!(google_event_id: "older", title: "Older", state: "completed", scheduled_starts_at: 9.days.ago, scheduled_ends_at: 9.days.ago + 1.hour, time_zone: "Europe/Berlin")
    older.attendances.create!(user: @absentee, display_name: "Absent", role: "builder", status: "absent")
    assert_includes render_for(@absentee).fetch(:text), "2nd missed session in a row. One more"
    older.attendances.find_by!(user: @absentee).update!(status: "present")
    assert_includes render_for(@absentee).fetch(:text), "1st missed session in a row"
    older.update!(state: "cancelled")
    assert_includes render_for(@absentee).fetch(:text), "1st missed session in a row"
  end

  test "attendees get the next session Meet link or its honest unavailable fallback" do
    @next_session.update!(meet_url: "https://meet.google.com/abc-defg-hij")
    email = render_for(@builder)
    assert_includes email.fetch(:text), "Google Meet: https://meet.google.com/abc-defg-hij"
    html = Nokogiri::HTML.fragment(email.fetch(:html))
    assert_equal "https://meet.google.com/abc-defg-hij", html.at_css("a[href='https://meet.google.com/abc-defg-hij']").text

    @next_session.update!(meet_url: nil)
    email = render_for(@builder)
    assert_includes email.fetch(:text), "The Google Meet link will be available on the session page."
    assert_includes email.fetch(:html), "The Google Meet link will be available on the session page."
    assert_not_includes email.fetch(:html), "https://meet.google.com/"
  end

  test "absentee mentions are escaped and replace the no-mention sentence" do
    email = WeeklyCherryEmail.new(builder_session: @session, recipient: @absentee, subject: "Sharper offers", mentions: [ "Rich said: <b>your demo was useful</b>." ]).render
    assert_includes email.fetch(:text), "The Builders said this about you this time:"
    assert_not_includes email.fetch(:text), "didn't mention you"
    assert_includes email.fetch(:html), "&lt;b&gt;your demo was useful&lt;/b&gt;"
  end

  test "new members without an attendance snapshot are not charged a missed session" do
    new_builder = User.create!(email: "new@example.com", enrollment_status: "active", verified_at: Time.current)
    assert_includes render_for(new_builder).fetch(:text), "No missed session has been counted"
  end

  test "escapes untrusted text in every email field" do
    email = WeeklyCherryEmail.new(builder_session: @session, recipient: @builder, subject: "Learning, number, action", tldr: [ "<script>alert('x')</script>", "Useful & honest." ]).render
    assert_not_includes email.fetch(:html), "<script>"
    assert_includes email.fetch(:html), "&lt;script&gt;"
  end

  test "rejects inactive recipients deleted records and malformed copy" do
    outsider = User.create!(email: "outside@example.com")
    assert_raises(ArgumentError) { render_for(outsider) }
    assert_raises(ArgumentError) { WeeklyCherryEmail.new(builder_session: @session, recipient: @builder, subject: "Bad\r\nBcc: evil@example.com", tldr: [ "Useful." ]).render }
    assert_raises(ArgumentError) { WeeklyCherryEmail.new(builder_session: @session, recipient: @builder, subject: "Good", tldr: Array.new(5, "Too much.")).render }
    @session.transcript.delete_content!
    assert_raises(ArgumentError) { render_for(@builder) }
  end

  test "does not invent a next date when there is no upcoming session" do
    @next_session.update!(state: "cancelled")
    assert_includes render_for(@builder).fetch(:text), "Next session time: to be confirmed"
  end

  private

  def render_for(user)
    WeeklyCherryEmail.new(builder_session: @session, recipient: user, subject: "Sharper offers, five customers, ship the page", tldr: [ "💎 Put the outcome first.", "🍒 Five useful conversations beat another feature." ]).render
  end
end
