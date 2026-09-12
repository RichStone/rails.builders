require "test_helper"

class BuilderSessionRecordImportTest < ActiveSupport::TestCase
  setup do
    @facilitator = User.create!(email: "facilitator@example.com", name: "Facilitator", facilitator: true, verified_at: Time.current)
    @builder = User.create!(email: "builder@example.com", name: "Builder", enrollment_status: "active", verified_at: Time.current)
    @program = Program.create!(name: "Continuous", starts_on: Date.new(2026, 8, 20), ends_on: Date.new(2026, 12, 17), capacity: 9, main_facilitator: @facilitator)
    @session = create_session("current", Time.zone.parse("2026-09-10 15:30"))
    @session.attendances.create!(user: @builder, display_name: "Builder", role: "builder", status: "present")
    @transcript = @session.create_transcript!
    @attributes = {
      wispr_meeting_id: "wispr-meeting-current",
      transcript: "Builder: I will speak with five customers.\nFacilitator: Ask about their last purchase.",
      summary_notes: "Five customer conversations are next.",
      session_analysis: "## Builder\n\n**Current project:** Onboarding",
      promises: [ { user_id: @builder.id, body: "Speak with five customers before the next session." } ],
      feedback: [ {
        author_id: @facilitator.id, recipient_id: @builder.id,
        body: "Ask about their last purchase, not hypothetical interest.",
        source: "transcript", sentiment: "idea", source_key: "turn-2"
      } ],
      chat: { content: "15:45 Facilitator: Start with the last purchase.", source: "google_meet" }
    }
  end

  test "atomically imports the complete record and encrypts private extracted content" do
    result = import

    assert_equal @transcript.id, result.id
    assert_equal "ready", @transcript.reload.state
    assert_equal @attributes[:transcript], @transcript.content
    assert_equal @attributes[:summary_notes], @transcript.summary_notes
    assert_equal @attributes[:session_analysis], @transcript.session_analysis
    assert_equal @attributes[:wispr_meeting_id], @transcript.wispr_meeting_id
    promise = @session.next_session_promises.sole
    feedback = @session.peer_feedbacks.sole
    chat = @session.reload.chat_log
    assert_equal @builder, promise.user
    assert_equal @facilitator, feedback.author
    assert_equal @builder, feedback.recipient
    assert_equal @attributes[:chat][:content], chat.content
    [ [ promise, :body ], [ feedback, :body ], [ chat, :content ] ].each do |record, field|
      assert_not_includes record.read_attribute_before_type_cast(field), record.public_send(field)
    end
  end

  test "repeating a Wispr import is a no-op and does not overwrite later manual edits" do
    import
    @transcript.update_session_context!(session_analysis: "Facilitator corrected the analysis.")
    @session.chat_log.update!(content: "Manually corrected chat.")
    @attributes[:promises].first[:body] = "A different promise."

    assert_no_difference [ "NextSessionPromise.count", "PeerFeedback.count", "BuilderSessionChatLog.count" ] do
      import
    end
    assert_equal "Facilitator corrected the analysis.", @transcript.reload.session_analysis
    assert_equal "Manually corrected chat.", @session.chat_log.reload.content
    assert_equal "Speak with five customers before the next session.", @session.next_session_promises.sole.body
  end

  test "a ready Google transcript is preserved while notes and derived records are added" do
    @transcript.update!(state: "ready", source: "google", content: "Existing complete Google transcript.")

    import

    assert_equal "Existing complete Google transcript.", @transcript.reload.content
    assert_equal "google", @transcript.source
    assert_equal @attributes[:summary_notes], @transcript.summary_notes
    assert_equal 1, @session.next_session_promises.count
  end

  test "invalid feedback rolls back transcript notes promises chat and source marker" do
    @attributes[:feedback].first[:recipient_id] = @facilitator.id

    assert_raises(ActiveRecord::RecordInvalid) { import }

    assert_equal "pending", @transcript.reload.state
    assert_nil @transcript.content
    assert_nil @transcript.summary_notes
    assert_nil @transcript.wispr_meeting_id
    assert_empty @session.next_session_promises.reload
    assert_empty @session.peer_feedbacks.reload
    assert_nil @session.reload.chat_log
  end

  test "conflicting chat does not replace a manually supplied fallback or partially import" do
    @session.create_chat_log!(content: "Manual complete chat.", source: "manual", imported_at: Time.current)

    assert_raises(ActiveRecord::RecordInvalid) { import }

    assert_equal "Manual complete chat.", @session.chat_log.reload.content
    assert_equal "pending", @transcript.reload.state
    assert_empty @session.next_session_promises.reload
  end

  test "optional chat can be supplied manually before or after the weekly import" do
    @attributes.delete(:chat)
    import
    assert_nil @session.reload.chat_log

    @session.create_chat_log!(content: "Manually supplied history.", source: "manual", imported_at: Time.current)
    import
    assert_equal "Manually supplied history.", @session.chat_log.reload.content
  end

  test "a different recording cannot be attached to an imported session" do
    import
    @attributes[:wispr_meeting_id] = "another-recording"

    assert_raises(ActiveRecord::RecordInvalid) { import }
    assert_equal "wispr-meeting-current", @transcript.reload.wispr_meeting_id
  end

  test "one recording cannot be imported into two sessions" do
    import
    other = create_session("other", @session.scheduled_starts_at + 1.week)
    @attributes[:promises] = []
    @attributes[:feedback] = []

    assert_raises(ActiveRecord::RecordInvalid) do
      BuilderSessionRecordImport.call(builder_session: other, attributes: @attributes)
    end
    assert_nil other.reload.transcript
    assert_nil other.chat_log
  end

  test "deleted session records erase derivatives and cannot be restored by the same or a new recording" do
    import
    @transcript.delete_content!

    assert_equal "deleted", @transcript.reload.state
    assert_equal "wispr-meeting-current", @transcript.wispr_meeting_id
    assert_nil @transcript.content
    assert_nil @session.reload.chat_log
    assert_empty @session.next_session_promises
    assert_empty @session.peer_feedbacks
    assert_raises(ActiveRecord::RecordInvalid) { import }
    @attributes[:wispr_meeting_id] = "new-recording"
    assert_raises(ActiveRecord::RecordInvalid) { import }
    assert_raises(ActiveRecord::RecordInvalid) do
      @session.next_session_promises.create!(@attributes[:promises].first)
    end
    assert_raises(ActiveRecord::RecordInvalid) do
      @session.peer_feedbacks.create!(@attributes[:feedback].first)
    end
    assert_raises(ActiveRecord::RecordInvalid) do
      @session.create_chat_log!(content: "Restored", source: "manual", imported_at: Time.current)
    end
  end

  test "live sessions cannot receive imported records" do
    @session.update!(state: "ready")

    assert_raises(ActiveRecord::RecordInvalid) { import }
    assert_equal "pending", @transcript.reload.state
  end

  test "promises and feedback require actual participants and bounded content" do
    outsider = User.create!(email: "absent@example.com")
    promise = @session.next_session_promises.new(user: outsider, body: "Ship it.")
    assert_not promise.valid?
    assert_includes promise.errors[:user], "must have participated in the session"
    promise.user = @builder
    promise.body = "a" * 501
    assert_not promise.valid?
    promise.body = "Ship it."
    promise.save!
    assert_not @session.next_session_promises.new(user: @builder, body: "Duplicate.").valid?

    feedback = @session.peer_feedbacks.new(@attributes[:feedback].first.merge(author_id: outsider.id))
    assert_not feedback.valid?
    feedback.author = @facilitator
    feedback.body = "a" * 701
    assert_not feedback.valid?
    feedback.body = "Try one small experiment."
    feedback.sentiment = "made-up"
    assert_not feedback.valid?
    feedback.sentiment = "constructive"
    feedback.source = "made-up"
    assert_not feedback.valid?
    feedback.source = "chat"
    feedback.save!
    assert_not @session.peer_feedbacks.new(@attributes[:feedback].first).valid?
  end

  test "feedback can address an expected absent builder but not an unrelated user or absent author" do
    absentee = User.create!(email: "missed@example.com", enrollment_status: "active")
    @session.attendances.create!(user: absentee, display_name: "Missed Builder", role: "builder", status: "absent")
    feedback = @session.peer_feedbacks.new(@attributes[:feedback].first.merge(recipient_id: absentee.id))
    assert feedback.save

    unrelated = User.create!(email: "unrelated@example.com", enrollment_status: "active")
    feedback.recipient = unrelated
    assert_not feedback.valid?
    assert_includes feedback.errors[:recipient], "must have been expected at the session"

    feedback.recipient = @builder
    feedback.author = absentee
    assert_not feedback.valid?
    assert_includes feedback.errors[:author], "must have participated in the session"
  end

  test "previous promise is from the immediately preceding completed session in the same program" do
    first = create_session("first", @session.scheduled_starts_at - 2.weeks)
    middle = create_session("middle", @session.scheduled_starts_at - 1.week)
    first.attendances.create!(user: @builder, display_name: "Builder", role: "builder", status: "present")
    old_promise = first.next_session_promises.create!(user: @builder, body: "An old commitment.")
    assert_nil @session.previous_promise_for(@builder)

    middle.attendances.create!(user: @builder, display_name: "Builder", role: "builder", status: "present")
    last_promise = middle.next_session_promises.create!(user: @builder, body: "Last week's commitment.")
    assert_equal last_promise, @session.previous_promise_for(@builder)

    middle.update!(state: "cancelled")
    assert_equal old_promise, @session.previous_promise_for(@builder)
    middle.update!(state: "completed")
    middle.create_transcript!(state: "deleted", deleted_at: Time.current)
    assert_nil @session.previous_promise_for(@builder)
  end

  test "a more recent promise in another program never enters the current timer" do
    other_program = Program.create!(name: "Other program", starts_on: @program.starts_on, ends_on: @program.ends_on, capacity: 9)
    unrelated = create_session("unrelated", @session.scheduled_starts_at - 1.day)
    unrelated.update!(program: other_program)
    unrelated.next_session_promises.create!(user: @facilitator, body: "Only relevant in the other program.")

    assert_nil @session.previous_promise_for(@facilitator)
    assert_nil @session.previous_promise_for(nil)
  end

  test "deleting a builder removes their promises and feedback in both directions" do
    import
    @session.peer_feedbacks.create!(@attributes[:feedback].first.merge(author_id: @builder.id, recipient_id: @facilitator.id, source_key: "reply"))

    @builder.destroy!

    assert_empty NextSessionPromise.all
    assert_empty PeerFeedback.all
    assert_nil @session.attendances.sole.user_id
  end

  private

  def import
    BuilderSessionRecordImport.call(builder_session: @session, attributes: @attributes)
  end

  def create_session(event_id, starts_at)
    @program.builder_sessions.create!(
      assigned_facilitator: @facilitator, google_event_id: event_id, title: "Weekly builders",
      scheduled_starts_at: starts_at, scheduled_ends_at: starts_at + 90.minutes,
      time_zone: "Europe/Berlin", state: "completed", started_at: starts_at, ended_at: starts_at + 90.minutes
    )
  end
end
