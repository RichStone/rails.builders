require "json"

abort "Timer QA setup is limited to development and test." unless Rails.env.development? || Rails.env.test?

facilitator = User.find_or_initialize_by(email: "timer-facilitator@example.test")
facilitator.assign_attributes(
  name: "Timer QA Facilitator",
  facilitator: true,
  enrollment_status: "active",
  verified_at: facilitator.verified_at || Time.current,
  public_profile: false,
  public_profile_approved: false
)
facilitator.save!

builders = [
  [ "timer-ada@example.test", "Ada Private Builder" ],
  [ "timer-ben@example.test", "Ben Private Builder" ],
  [ "timer-cora@example.test", "Cora Private Builder" ],
  [ "timer-dion@example.test", "Dion Private Builder" ],
  [ "timer-erin@example.test", "Erin Private Builder" ]
].map do |email, name|
  User.find_or_initialize_by(email:).tap do |builder|
    builder.assign_attributes(
      name:,
      facilitator: false,
      administrator: false,
      enrollment_status: "active",
      verified_at: builder.verified_at || Time.current,
      public_profile: false,
      public_profile_approved: false
    )
    builder.save!
  end
end

excluded_builder = User.find_or_initialize_by(email: "timer-waitlisted@example.test")
excluded_builder.assign_attributes(
  name: "Waitlisted QA Builder",
  facilitator: false,
  administrator: false,
  enrollment_status: "waitlisted",
  verified_at: excluded_builder.verified_at || Time.current,
  public_profile: false,
  public_profile_approved: false
)
excluded_builder.save!

program = Program.current || Program.create!(
  name: "Timer QA Program",
  starts_on: Date.current,
  ends_on: 4.months.from_now.to_date,
  capacity: 99,
  main_facilitator: facilitator
)

run_id = Time.current.strftime("%Y%m%d%H%M%S")
starts_at = 10.minutes.from_now.change(sec: 0)
titles = [
  "Timer QA 1 — Full lifecycle",
  "Timer QA 2 — Negative clock",
  "Timer QA 3 — Attendance insertion",
  "Timer QA 4 — Fresh Rich test",
  "Timer QA 5 — Fresh Rich test"
]
sessions = titles.each_with_index.map do |title, index|
  program.builder_sessions.create!(
    assigned_facilitator: facilitator,
    google_event_id: "timer-qa-#{run_id}-#{index + 1}",
    title:,
    description: "Synthetic local-only timer QA data. Every listed Builder has a private profile.",
    meet_url: "https://meet.google.com/abc-defg-hij",
    scheduled_starts_at: starts_at + index.hours,
    scheduled_ends_at: starts_at + index.hours + 90.minutes,
    time_zone: "Europe/Madrid"
  )
end

puts JSON.pretty_generate(
  facilitator_email: facilitator.email,
  private_builder_ids: builders.map(&:id),
  excluded_builder_id: excluded_builder.id,
  sessions: sessions.map { |session| { id: session.id, title: session.title, path: Rails.application.routes.url_helpers.builder_session_path(session) } },
  sign_in_path: Rails.application.routes.url_helpers.verify_email_path(token: facilitator.generate_token_for(:email_verification))
)
