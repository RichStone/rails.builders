class WeeklyCherryDelivery < ApplicationRecord
  belongs_to :builder_session_transcript
  belongs_to :user

  serialize :copy, coder: JSON
  encrypts :copy

  scope :pending, -> { where(sent_at: nil, skipped_at: nil, failed_at: nil) }

  def self.summary_recipient(session)
    [ session.assigned_facilitator, session.program.main_facilitator ].compact.find do |candidate|
      candidate.receives_weekly_cherry? && (candidate.facilitator? || candidate.administrator?)
    end
  end

  def self.publish!(transcript, edition)
    session = transcript.builder_session
    raise ArgumentError, "A completed, retained transcript is required" unless session.state == "completed" && transcript.state == "ready"
    return if transcript.weekly_cherry_queued_at?

    unless edition.is_a?(Hash) && edition["subject"].present? &&
        [ edition["tldr"], edition["speaker_updates"] ].any? { |recap| recap.is_a?(Array) && recap.any? }
      raise ArgumentError, "The Weekly Builders Cherry requires a subject and shared recap"
    end

    mentions = edition.fetch("mentions", {})
    raise ArgumentError, "Supply mentions by Builder ID" unless mentions.is_a?(Hash)

    WeeklyCherryEmail.recipients_for(session).each do |recipient|
      next unless recipient.receives_weekly_cherry?

      email = WeeklyCherryEmail.new(
        builder_session: session, recipient: recipient, subject: edition["subject"], tldr: edition.fetch("tldr", []),
        speaker_updates: edition.fetch("speaker_updates", []),
        mentions: mentions.fetch(recipient.id.to_s, []), recommendations: edition.fetch("recommendations", []),
        first_names: edition.fetch("first_names", {}),
        warning_notice: edition["warning_notice"], info_notice: edition["info_notice"]
      ).render
      attendance = session.attendances.find_by(user: recipient)&.status
      transcript.weekly_cherry_deliveries.create!(user: recipient, copy: email.merge(attendance: attendance))
    end
    if (facilitator = summary_recipient(session))
      transcript.weekly_cherry_deliveries.create!(user: facilitator, summary: true)
    end
    transcript.update!(weekly_cherry_queued_at: Time.current)
  end

  def process!
    session = builder_session_transcript.builder_session
    session.with_lock do
      reload
      return if processed?
      return if summary? && other_deliveries.pending.exists?

      transcript = builder_session_transcript.reload
      unless session.state == "completed" && transcript.state == "ready" && eligible?(session)
        finish!(skipped_at: Time.current)
        return
      end
      if first_attempted_at? && first_attempted_at <= 23.hours.ago
        finish!(failed_at: Time.current)
        return
      end

      update!(first_attempted_at: Time.current, copy: summary? ? summary_copy : copy) unless first_attempted_at?
    end

    session.with_lock do
      reload
      return if processed?
      if first_attempted_at <= 23.hours.ago
        finish!(failed_at: Time.current)
        return
      end
      unless session.state == "completed" && builder_session_transcript.reload.state == "ready" && eligible?(session)
        finish!(skipped_at: Time.current)
        return
      end

      WeeklyCherryMailer.with(copy: copy, delivery_id: id, summary: summary?).edition.deliver_now
      finish!(sent_at: Time.current)
    end
  end

  private

  def processed? = sent_at? || skipped_at? || failed_at?

  def eligible?(session)
    recipient = user.reload
    return false unless recipient.receives_weekly_cherry?
    return false if copy && copy["to"] != recipient.email

    facilitator = session.assigned_facilitator || session.program.main_facilitator
    if summary?
      recipient == self.class.summary_recipient(session) &&
        (copy.nil? || other_deliveries.where(id: copy.fetch("member_delivery_ids")).count == copy.fetch("member_delivery_ids").length)
    else
      (recipient.active? || recipient == facilitator) && copy["attendance"] == session.attendances.find_by(user: recipient)&.status
    end
  end

  def other_deliveries
    builder_session_transcript.weekly_cherry_deliveries.where(summary: false)
  end

  def summary_copy
    members = other_deliveries
    sent_to_others = members.where.not(sent_at: nil).where.not(user_id: user_id).includes(:user).order(:id).to_a
    rows = sent_to_others.map do |delivery|
      { name: delivery.copy.fetch("recipient_name") { delivery.user.name.to_s.split.first || "Builder" }, personal: delivery.copy.fetch("personal") }
    end
    session = builder_session_transcript.builder_session
    {
      "to" => user.email,
      "subject" => "Weekly Builders Cherry delivery summary · #{session.scheduled_starts_at.in_time_zone(session.time_zone).strftime('%-d %B %Y')}",
      "session_url" => "https://rails.builders/sessions/#{session.id}",
      "members" => rows.map(&:stringify_keys),
      "member_delivery_ids" => sent_to_others.map(&:id),
      "sent" => members.where.not(sent_at: nil).count,
      "skipped" => members.where.not(skipped_at: nil).count,
      "failed" => members.where.not(failed_at: nil).count
    }
  end

  def finish!(**status)
    if summary?
      update!(**status, copy: nil)
      other_deliveries.update_all(copy: nil)
    elsif status.key?(:sent_at) && builder_session_transcript.weekly_cherry_deliveries.exists?(summary: true)
      update!(**status, copy: copy.slice("personal", "recipient_name"))
    else
      update!(**status, copy: nil)
    end
  end
end
