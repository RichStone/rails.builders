class WeeklyCherryEmail
  SENTIMENT_EMOJIS = { "encouraging" => "🙌", "constructive" => "🛠️", "idea" => "💡", "question" => "🤔" }.freeze

  def self.recipients_for(builder_session)
    facilitator = builder_session.assigned_facilitator || builder_session.program.main_facilitator
    (User.active.order(:id).to_a + [ facilitator ]).compact.uniq(&:id)
  end

  def initialize(builder_session:, recipient:, subject:, tldr: [], mentions: [], cherry_cid: "weekly-cherry")
    @builder_session = builder_session
    @recipient = recipient
    @subject = subject
    @tldr = tldr
    @mentions = mentions
    @cherry_cid = cherry_cid
  end

  # Render only. Gmail draft creation and facilitator delivery are explicit agent actions.
  def render
    attended = @builder_session.attendances.exists?(user: @recipient, status: "present")
    validate!(attended: attended)
    promise = @builder_session.next_session_promises.find_by(user: @recipient) if attended
    next_session = @builder_session.program.builder_sessions.where(state: "ready")
      .where("scheduled_starts_at > ?", [ @builder_session.scheduled_starts_at, Time.current ].max)
      .order(:scheduled_starts_at).first
    next_time = if next_session
      "#{next_session.scheduled_starts_at.in_time_zone(next_session.time_zone).strftime('%A, %-d %B at %H:%M %Z')} (#{next_session.time_zone})"
    end
    assigns = {
      recipient_name: @recipient.name.presence || "Builder",
      session_date: @builder_session.scheduled_starts_at.in_time_zone(@builder_session.time_zone).strftime("%-d %B %Y"),
      session_url: "https://rails.builders/sessions/#{@builder_session.id}",
      attended: attended,
      promise: promise&.body,
      feedback: @builder_session.peer_feedbacks.where(recipient: @recipient).includes(:author).order(:id).map { |item| { name: item.author.name.presence || "Builder", body: item.body, emoji: SENTIMENT_EMOJIS.fetch(item.sentiment) } },
      tldr: @tldr,
      mentions: @mentions,
      absence_warning: attended ? nil : absence_warning,
      next_time: next_time,
      next_meet_url: next_session&.meet_url.presence&.then { |url| url if GoogleWorkspace::MeetLink.canonical?(url) },
      cherry_cid: @cherry_cid
    }
    renderer = ApplicationController.renderer.new(http_host: "rails.builders", https: true)
    {
      to: @recipient.email,
      subject: attended ? @subject : "You missed #{@subject}",
      html: renderer.render(template: "weekly_cherry_email/weekly", formats: [ :html ], layout: "layouts/mailer", assigns: assigns),
      text: renderer.render(template: "weekly_cherry_email/weekly", formats: [ :text ], layout: false, assigns: assigns)
    }
  end

  private

  def absence_warning
    count = 0
    @builder_session.program.builder_sessions.where(state: "completed")
      .where("scheduled_starts_at <= ?", @builder_session.scheduled_starts_at)
      .order(scheduled_starts_at: :desc, id: :desc).each do |session|
      attendance = session.attendances.find_by(user: @recipient)
      break unless attendance&.status == "absent"

      count += 1
    end
    return "No missed session has been counted: there is no attendance record for you this week." if count.zero?

    warning = case count
    when 1 then "Two more and your Rails.Builders spot is at risk"
    when 2 then "One more and your Rails.Builders spot is at risk"
    else "You have reached the three-miss limit; Rich needs to review your spot"
    end
    "This is your #{count.ordinalize} missed session in a row. #{warning} (you remember, gamification 🎲)."
  end

  def validate!(attended:)
    raise ArgumentError, "A completed, retained session record is required" unless @builder_session.state == "completed" && @builder_session.transcript&.state == "ready"
    raise ArgumentError, "Recipient must be an active member or this session's facilitator" unless self.class.recipients_for(@builder_session).include?(@recipient)
    raise ArgumentError, "Use a short, single-line subject" unless @subject.is_a?(String) && @subject.present? && @subject.length <= 180 && !@subject.match?(/[\r\n]/)
    raise ArgumentError, "Use up to four concise TL;DR items" unless @tldr.is_a?(Array) && @tldr.length.in?((attended ? 1 : 0)..4) && @tldr.all? { |line| line.is_a?(String) && line.present? && line.length <= 500 }
    raise ArgumentError, "Use up to five evidenced mentions" unless @mentions.is_a?(Array) && @mentions.length <= 5 && @mentions.all? { |line| line.is_a?(String) && line.present? && line.length <= 700 }
    raise ArgumentError, "Invalid image content ID" unless @cherry_cid.is_a?(String) && @cherry_cid.match?(/\A[a-zA-Z0-9_.@-]{1,100}\z/)
  end
end
