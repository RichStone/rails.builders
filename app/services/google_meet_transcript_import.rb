class GoogleMeetTranscriptImport
  def initialize(transcript:, client:)
    @transcript = transcript
    @client = client
  end

  def call
    attempted_at = Time.current
    result = client.transcript_for(transcript.builder_session)

    transcript.with_lock do
      return transcript unless transcript.state.in?(BuilderSessionTranscript::AUTOMATIC_IMPORT_STATES)

      attempts = transcript.attempts + 1
      if result[:status] == :ready
        transcript.update!(
          state: "ready",
          source: "google",
          content: format_segments(result.fetch(:segments)),
          google_conference_record_name: result[:conference_record_name],
          google_transcript_names: result.fetch(:transcript_names, []).to_json,
          attempts: attempts,
          last_attempted_at: attempted_at,
          next_attempt_at: nil,
          imported_at: attempted_at,
          last_error_code: nil
        )
      else
        transcript.update!(
          state: "processing",
          attempts: attempts,
          last_attempted_at: attempted_at,
          next_attempt_at: attempted_at + [ attempts * 5, 60 ].min.minutes,
          last_error_code: nil
        )
      end
    end
    transcript
  end

  private

  attr_reader :transcript, :client

  def format_segments(segments)
    zone = transcript.builder_session.time_zone
    segments.map do |segment|
      time = segment.fetch(:started_at).in_time_zone(zone).strftime("%H:%M")
      "#{time} · #{segment.fetch(:speaker)}\n#{segment.fetch(:text)}"
    end.join("\n\n")
  end
end
