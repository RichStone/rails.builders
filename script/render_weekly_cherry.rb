# bin/rails runner script/render_weekly_cherry.rb < private-email-copy.json
# Output contains private recipient data: use a protected local file, never CI logs.
input = JSON.parse($stdin.read)
builder_session = Program.current.builder_sessions.find(input.fetch("session_id"))
recipients = WeeklyCherryEmail.recipients_for(builder_session).index_by(&:id)
emails = input.fetch("emails").map do |copy|
  recipient = recipients.fetch(copy.fetch("user_id"))
  WeeklyCherryEmail.new(
    builder_session: builder_session,
    recipient: recipient,
    subject: copy.fetch("subject"),
    tldr: copy.fetch("tldr", []),
    mentions: copy.fetch("mentions", []),
    warning_notice: input["warning_notice"],
    info_notice: input["info_notice"]
  ).render
end
abort "Duplicate recipients are not allowed" unless emails.map { |email| email.fetch(:to) }.uniq.length == emails.length
puts JSON.generate(emails)
