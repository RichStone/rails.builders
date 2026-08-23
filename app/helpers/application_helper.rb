module ApplicationHelper
  PUBLIC_MEET_LINK = %r{(?:(?:https?:)?//)?meet\.google\.com/[^\s<]+}i
  PUBLIC_MEET_CODE = /\b[a-z]{3}-[a-z]{4}-[a-z]{3}\b/i

  def profile_visibility_description(user)
    return "Private. Only you and administrators can see it." unless user.public_profile?
    return "Waiting for facilitator approval." unless user.public_profile_approved?
    return "Published on the homepage." if user.og? || user.active? || user.waitlisted?

    "Approved and ready to appear when you become an Active Builder."
  end

  def user_role_labels(user)
    labels = []
    labels << "OG" if user.og?
    labels << "Facilitator" if user.facilitator?
    labels << "Admin" if user.administrator?
    labels.presence || [ "Registrant" ]
  end

  def public_session_facilitator_name(builder_session)
    facilitator = builder_session.assigned_facilitator
    return "Rails Builders" unless facilitator&.publicly_visible?

    facilitator.name.presence || "Rails Builders"
  end

  def public_session_title(builder_session)
    builder_session.title.gsub(PUBLIC_MEET_LINK, "Google Meet").gsub(PUBLIC_MEET_CODE, "Google Meet")
  end
end
