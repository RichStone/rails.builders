module BuilderSessionsHelper
  AWARD_ART = {
    "new-builders" => "newcomers",
    "newcomers" => "newcomers",
    "most-business-progress" => "business",
    "most-business-value" => "business",
    "most-business-value-progress" => "business",
    "most-traffic-progress" => "social",
    "most-social-traffic" => "social",
    "best-customer-discovery" => "organic",
    "most-organic-traffic" => "organic",
    "most-aeo-converted-traffic" => "aeo",
    "most-product-progress" => "product"
  }.freeze

  FEEDBACK_SENTIMENTS = {
    "encouraging" => [ "🙌", "Encouraging" ],
    "constructive" => [ "🛠️", "Constructive" ],
    "idea" => [ "💡", "Idea" ],
    "question" => [ "🤔", "Question" ]
  }.freeze

  def session_builder_name(user)
    user&.name.presence || "Builder"
  end

  def award_illustration(title)
    type = AWARD_ART[title.parameterize]
    return unless type

    image_tag "awards/#{type}.webp", alt: "", width: 1280, height: 720, loading: "lazy", class: "session-award-art"
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
