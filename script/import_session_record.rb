# bin/rails runner script/import_session_record.rb < private-session-record.json
# Keep input outside git; never put private transcript text in command arguments.
input = JSON.parse($stdin.read)
builder_session = Program.current.builder_sessions.find(input.fetch("session_id"))
expected_start = Time.iso8601(input.fetch("expected_scheduled_starts_at"))
abort "Session schedule changed; verify the recording match again" unless builder_session.scheduled_starts_at == expected_start

transcript = BuilderSessionRecordImport.call(builder_session: builder_session, attributes: input.fetch("record"))
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
  chat_saved: builder_session.chat_log.present?
)
