class CommunitySnapshot
  def initialize(program:, generated_at:, avatar_url: ->(_builder) { })
    @program = program
    @generated_at = generated_at
    @avatar_url = avatar_url
  end

  def as_json
    {
      generated_at: generated_at.iso8601,
      community: {
        name: "Rails Builders",
        program: program_data,
        public_builders: public_builders.map { |builder| builder_data(builder) },
        past_sessions: past_sessions.map { |session| session_data(session) }
      },
      privacy: {
        attendance_names: "Included only for builders with approved public profiles.",
        excluded: [
          "emails and private profiles",
          "transcripts and chat logs",
          "session notes, promises, and peer feedback",
          "Meet links and Google Calendar identifiers",
          "arrival times, speaker order, and detailed timing"
        ]
      }
    }
  end

  private

  attr_reader :program, :generated_at, :avatar_url

  def public_builders
    @public_builders ||= User.publicly_visible.includes(:products, avatar_attachment: :blob).order(:name, :id).to_a
  end

  def past_sessions
    @past_sessions ||= program.builder_sessions
      .where("scheduled_starts_at < ?", generated_at)
      .includes(:assigned_facilitator, attendances: :user)
      .order(scheduled_starts_at: :desc, id: :desc)
      .to_a
  end

  def program_data
    {
      name: program.name,
      starts_on: program.starts_on.iso8601,
      ends_on: program.ends_on.iso8601,
      capacity: program.capacity,
      occupied_seats: program.occupied_seats,
      public_builder_count: public_builders.size,
      past_session_count: past_sessions.size
    }
  end

  def builder_data(builder)
    {
      name: builder.name,
      role: builder.facilitator? ? "facilitator" : "builder",
      community_status: community_status(builder),
      testimonial: builder.testimonial,
      avatar_url: avatar_url.call(builder),
      products: builder.products.sort_by { |product| [ product.focus? ? 0 : 1, product.name.downcase ] }.map do |product|
        { name: product.name, url: product.url, focus: product.focus? }
      end
    }
  end

  def community_status(builder)
    return "active" if builder.active?
    return "waitlisted" if builder.waitlisted?

    "preparing"
  end

  def session_data(session)
    attendances = session.attendances.to_a
    {
      id: session.id,
      title: session.public_title,
      status: session.state,
      scheduled_starts_at: session.scheduled_starts_at.iso8601,
      scheduled_ends_at: session.scheduled_ends_at.iso8601,
      time_zone: session.time_zone,
      started_at: session.started_at&.iso8601,
      ended_at: session.ended_at&.iso8601,
      facilitator: public_facilitator_name(session),
      attendance: {
        recorded: attendances.size,
        present: attendances.count { |attendance| attendance.status == "present" },
        absent: attendances.count { |attendance| attendance.status == "absent" },
        public_profiles: attendances.filter_map { |attendance| public_attendance_data(attendance) }
          .sort_by { |attendance| [ attendance[:name].downcase, attendance[:role] ] }
      }
    }
  end

  def public_facilitator_name(session)
    facilitator = session.assigned_facilitator
    facilitator.name if facilitator&.publicly_visible?
  end

  def public_attendance_data(attendance)
    builder = attendance.user
    return unless builder&.publicly_visible?

    { name: builder.name, role: attendance.role, status: attendance.status }
  end
end
