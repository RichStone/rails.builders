class WeeklyCherryEmail
  SENTIMENT_EMOJIS = { "encouraging" => "🙌", "constructive" => "🛠️", "idea" => "💡", "question" => "🤔" }.freeze

  def self.recipients_for(builder_session)
    facilitator = builder_session.assigned_facilitator || builder_session.program.main_facilitator
    (User.active.order(:id).to_a + [ facilitator ]).compact.uniq(&:id)
  end

  def initialize(builder_session:, recipient:, subject:, tldr: [], mentions: [], recommendations: [], warning_notice: nil, info_notice: nil, cherry_cid: "weekly-cherry")
    @builder_session = builder_session
    @recipient = recipient
    @subject = subject
    @tldr = tldr
    @mentions = mentions
    @recommendations = recommendations.is_a?(Array) ? recommendations.map { |group| group.is_a?(Hash) ? group.deep_symbolize_keys : group } : recommendations
    @warning_notice = warning_notice
    @info_notice = info_notice
    @cherry_cid = cherry_cid
  end

  # Render only. Gmail draft creation and facilitator delivery are explicit agent actions.
  def render
    attended = @builder_session.attendances.exists?(user: @recipient, status: "present")
    validate!(attended: attended)
    promise = if attended
      @builder_session.next_session_promises.find_by(user: @recipient)
    else
      @builder_session.previous_promise_for(@recipient)
    end
    upcoming_sessions = @builder_session.program.builder_sessions.where(state: "ready")
      .where("scheduled_starts_at > ?", [ @builder_session.scheduled_starts_at, Time.current ].max)
      .order(:scheduled_starts_at)
    next_session = upcoming_sessions.first
    skipping_next_session = next_session&.attendances&.exists?(user: @recipient, status: "absent")
    if skipping_next_session
      skipped_session_ids = BuilderSessionAttendance.where(user: @recipient, status: "absent").select(:builder_session_id)
      return_session = upcoming_sessions.where.not(id: skipped_session_ids).first
    end
    assigns = {
      recipient_name: @recipient.name.to_s.split.first || "Builder",
      session_date: @builder_session.scheduled_starts_at.in_time_zone(@builder_session.time_zone).strftime("%-d %B %Y"),
      session_url: "https://rails.builders/sessions/#{@builder_session.id}",
      attended: attended,
      promise: promise&.body,
      feedback: @builder_session.peer_feedbacks.where(recipient: @recipient).includes(:author).order(:id).map { |item| { name: item.author.name.to_s.split.first || "Builder", body: item.body, emoji: SENTIMENT_EMOJIS.fetch(item.sentiment) } },
      tldr: @tldr,
      mentions: @mentions,
      recommendations: @recommendations,
      warning_notice: @warning_notice,
      info_notice: @info_notice,
      absence_warning: attended ? nil : absence_warning,
      next_time: session_time(next_session),
      next_meet_url: session_meet_url(next_session),
      skipping_next_session: skipping_next_session,
      return_time: session_time(return_session),
      return_meet_url: session_meet_url(return_session),
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

  def session_time(session)
    return unless session

    "#{session.scheduled_starts_at.in_time_zone(session.time_zone).strftime('%A, %-d %B at %H:%M %Z')} (#{session.time_zone})"
  end

  def session_meet_url(session)
    session&.meet_url.presence&.then { |url| url if GoogleWorkspace::MeetLink.canonical?(url) }
  end

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

    limit = @builder_session.program.consecutive_absence_limit
    remaining = limit - count
    warning = if remaining.positive?
      remaining_label = { 1 => "One", 2 => "Two" }.fetch(remaining, remaining.to_s)
      "#{remaining_label} more and your Rails.Builders spot is at risk"
    else
      limit_label = limit == 3 ? "three" : limit
      "You have reached the #{limit_label}-miss limit; Rich needs to review your spot"
    end
    "This is your #{count.ordinalize} missed session in a row. #{warning} (you remember, gamification 🎲)."
  end

  def validate!(attended:)
    raise ArgumentError, "A completed, retained session record is required" unless @builder_session.state == "completed" && @builder_session.transcript&.state == "ready"
    raise ArgumentError, "Recipient must be an active member or this session's facilitator" unless self.class.recipients_for(@builder_session).include?(@recipient)
    raise ArgumentError, "Use a short, single-line subject" unless @subject.is_a?(String) && @subject.present? && @subject.length <= 180 && !@subject.match?(/[\r\n]/)
    raise ArgumentError, "Use up to four concise TL;DR items" unless @tldr.is_a?(Array) && @tldr.length.in?((attended ? 1 : 0)..4) && @tldr.all? { |line| line.is_a?(String) && line.present? && line.length <= 500 }
    raise ArgumentError, "Use up to five evidenced mentions" unless @mentions.is_a?(Array) && @mentions.length <= 5 && @mentions.all? { |line| line.is_a?(String) && line.present? && line.length <= 700 }
    raise ArgumentError, "Use up to 12 recommendation groups with concise labels and safe HTTP(S) links" unless valid_recommendations?
    raise ArgumentError, "Use concise plain-text edition notices" unless [ @warning_notice, @info_notice ].all? { |notice| notice.nil? || (notice.is_a?(String) && notice.present? && notice.length <= 1_000) }
    raise ArgumentError, "Invalid image content ID" unless @cherry_cid.is_a?(String) && @cherry_cid.match?(/\A[a-zA-Z0-9_.@-]{1,100}\z/)
  end

  def valid_recommendations?
    @recommendations.is_a?(Array) && @recommendations.length <= 12 && @recommendations.all? do |group|
      group.is_a?(Hash) && recommendation_text?(group[:title], 120) &&
        group[:links].is_a?(Array) && group[:links].length.in?(1..20) && group[:links].all? do |link|
          link.is_a?(Hash) && recommendation_text?(link[:label], 300) && safe_recommendation_url?(link[:url])
        end
    end
  end

  def recommendation_text?(text, limit)
    text.is_a?(String) && text.present? && text.length <= limit && !text.match?(/[\x00-\x1f\x7f]/)
  end

  def safe_recommendation_url?(url)
    return false unless url.is_a?(String) && url.length <= 2_048 && !url.match?(/[\x00-\x20\x7f]/)

    uri = URI.parse(url)
    uri.is_a?(URI::HTTP) && uri.host.present? && uri.userinfo.nil?
  rescue URI::InvalidURIError
    false
  end
end
