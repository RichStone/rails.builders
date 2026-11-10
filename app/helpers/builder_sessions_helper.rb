module BuilderSessionsHelper
  FEEDBACK_SENTIMENTS = {
    "encouraging" => [ "🙌", "Encouraging" ],
    "constructive" => [ "🛠️", "Constructive" ],
    "idea" => [ "💡", "Idea" ],
    "question" => [ "🤔", "Question" ]
  }.freeze

  def session_builder_name(user)
    user&.name.presence || "Builder"
  end

  def session_record_label(session)
    "#{session.scheduled_starts_at.in_time_zone(session.time_zone).to_date.to_fs(:long)} · #{session.title}"
  end

  def feedback_conversations(builder_session)
    builder_session.peer_feedbacks.includes(:author, :recipient).order(:id)
      .group_by { |feedback| [ feedback.author_id, feedback.recipient_id ].sort }
      .values
  end

  def feedback_sentiment(feedback)
    FEEDBACK_SENTIMENTS.fetch(feedback.sentiment)
  end
end
