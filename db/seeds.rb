program = Program.find_or_initialize_by(name: "Continuous")
program.update!(starts_on: Date.new(2026, 8, 20), ends_on: Date.new(2026, 12, 17), capacity: 9)

og_emails = Rails.configuration.x.rails_builders.og_emails
facilitator_email = Rails.configuration.x.rails_builders.facilitator_email

og_emails.each do |email|
  facilitator = email == facilitator_email
  user = User.find_or_initialize_by(email: email)
  user.assign_attributes(
    og: true,
    name: facilitator ? "Rich Steinmetz" : nil,
    public_profile: false,
    public_profile_approved: false,
    administrator: facilitator,
    facilitator: facilitator
  )
  if facilitator
    user.verified_at ||= Time.current
    user.enrollment_status = "active"
  end
  user.save!

  if facilitator
    product = user.products.find_or_initialize_by(name: "Loop Labs 🧪")
    product.update!(url: "https://looplabs.cc", focus: true)
    user.update!(public_profile: true, public_profile_approved: true)
  end
end
