class BuilderSessionRecordImport
  def self.call(builder_session:, attributes:)
    new(builder_session:, attributes:).call
  end

  def initialize(builder_session:, attributes:)
    @builder_session = builder_session
    @attributes = attributes.deep_symbolize_keys
  end

  def call
    builder_session.with_lock do
      reject_record!(builder_session, "Session must be completed and its record must not be deleted") unless builder_session.session_record_writable?
      transcript = builder_session.transcript || builder_session.create_transcript!

      transcript.with_lock do
        meeting_id = attributes.fetch(:wispr_meeting_id).to_s.strip
        reject_record!(transcript, "Wispr meeting is required") if meeting_id.blank?
        if transcript.wispr_meeting_id.present?
          reject_record!(transcript, "A different Wispr meeting is already attached") unless transcript.wispr_meeting_id == meeting_id
          next transcript
        end

        context = attributes.slice(:summary_notes, :session_analysis)
        if transcript.state == "ready"
          transcript.update_session_context!(context)
        else
          transcript.replace_with_manual!(attributes.fetch(:transcript), **context)
        end

        attributes.fetch(:promises, []).each do |promise|
          builder_session.next_session_promises.create!(promise.slice(:user_id, :body))
        end
        attributes.fetch(:feedback, []).each do |feedback|
          builder_session.peer_feedbacks.create!(feedback.slice(:author_id, :recipient_id, :body, :sentiment, :source, :source_key))
        end
        import_chat!(attributes[:chat]) if attributes[:chat]
        transcript.update!(wispr_meeting_id: meeting_id)
        transcript
      end
    end
  end

  private

  attr_reader :builder_session, :attributes

  def import_chat!(chat)
    if (existing = builder_session.chat_log)
      reject_record!(existing, "Chat history has already been saved with different content") unless existing.content == chat.fetch(:content)
    else
      builder_session.create_chat_log!(chat.slice(:content, :source).merge(imported_at: Time.current))
    end
  end

  def reject_record!(record, message)
    record.errors.add(:base, message)
    raise ActiveRecord::RecordInvalid, record
  end
end
