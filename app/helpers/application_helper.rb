module ApplicationHelper
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
end
