# bin/rails runner script/import_session_record.rb < private-session-record.json
# Keep input outside git; never put private transcript text in command arguments.
begin
  input = JSON.parse($stdin.read)
rescue JSON::ParserError
  abort "Session record input must be valid JSON"
end
abort "Session record input must be a JSON object" unless input.is_a?(Hash)

session_id = Integer(input["session_id"].to_s, 10, exception: false)
record = input["record"]
edition = input["weekly_cherry"]
unless session_id && (record.is_a?(Hash) && record.key?("wispr_meeting_id") || record.nil? && edition.is_a?(Hash))
  abort "Supply session_id and a session record, or weekly_cherry for a transcript that is already ready"
end

if record && record["wispr_meeting_id"].nil? && (!record["transcript"].is_a?(String) || record["transcript"].blank?)
  abort "A pasted transcript is required for a manual import"
end
begin
  expected_start = Time.iso8601(input["expected_scheduled_starts_at"].to_s)
rescue ArgumentError
  abort "Supply expected_scheduled_starts_at as an ISO 8601 timestamp"
end

builder_session = Program.current.builder_sessions.find_by(id: session_id)
abort "Session not found in the current program" unless builder_session
begin
  transcript = builder_session.with_lock do
    abort "Session schedule changed; verify the recording match again" unless builder_session.scheduled_starts_at == expected_start
    saved = record ? BuilderSessionRecordImport.call(builder_session: builder_session, attributes: record) : builder_session.transcript
    abort "A completed, retained transcript is required" unless saved

    WeeklyCherryDelivery.publish!(saved, edition) if input.key?("weekly_cherry")
    saved
  end
rescue ActiveRecord::RecordInvalid => error
  abort error.record.errors.full_messages.join(", ")
rescue ArgumentError => error
  abort error.message
end
deliveries = transcript.weekly_cherry_deliveries
puts JSON.generate(
  session_id: builder_session.id,
  state: transcript.state,
  wispr_meeting_id: transcript.wispr_meeting_id,
  transcript_characters: transcript.content.to_s.length,
  transcript_sha256: Digest::SHA256.hexdigest(transcript.content.to_s),
  summary_characters: transcript.summary_notes.to_s.length,
  analysis_characters: transcript.session_analysis.to_s.length,
  promises: builder_session.next_session_promises.count,
  feedback: builder_session.peer_feedbacks.count,
  progress_entries: builder_session.builder_progress_entries.count,
  chat_saved: builder_session.chat_log.present?,
  weekly_cherry_queued_at: transcript.weekly_cherry_queued_at,
  weekly_cherry_deliveries: deliveries.group(:summary).count,
  weekly_cherry_pending: deliveries.pending.count,
  weekly_cherry_sent: deliveries.where.not(sent_at: nil).count,
  weekly_cherry_summary_sent: deliveries.where(summary: true).where.not(sent_at: nil).exists?,
  weekly_cherry_skipped: deliveries.where.not(skipped_at: nil).count,
  weekly_cherry_unconfirmed: deliveries.where.not(failed_at: nil).count
)
