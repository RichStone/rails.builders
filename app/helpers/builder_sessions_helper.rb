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

  def feedback_conversations(builder_session)
    builder_session.peer_feedbacks.includes(:author, :recipient).order(:id)
      .group_by { |feedback| [ feedback.author_id, feedback.recipient_id ].sort }
      .values
  end

  def feedback_sentiment(feedback)
    FEEDBACK_SENTIMENTS.fetch(feedback.sentiment)
  end
end
