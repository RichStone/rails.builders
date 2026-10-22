require "test_helper"

class GoogleWorkspace::CalendarClientTest < ActiveSupport::TestCase
  Calendar = Google::Apis::CalendarV3

  class FakeService
    attr_reader :calendar_list_calls, :event_calls, :event_get_calls, :event_patch_calls, :event_delete_calls, :calendar_get_calls
    attr_accessor :delete_error, :event_get_error, :calendar_error, :calendar_access_role

    def initialize(calendar_pages: [], event_pages: [], events: {})
      @calendar_pages = calendar_pages
      @event_pages = event_pages
      @events = events
      @calendar_list_calls = []
      @event_calls = []
      @event_get_calls = []
      @event_patch_calls = []
      @event_delete_calls = []
      @calendar_get_calls = []
      @calendar_access_role = "owner"
    end

    def get_calendar_list(calendar_id, fields:)
      if fields == "id,accessRole"
        @calendar_get_calls << { calendar_id:, fields: }
        raise calendar_error if calendar_error

        return Calendar::CalendarListEntry.new(id: calendar_id, access_role: calendar_access_role)
      end
      raise unless calendar_id == "primary"
      raise unless fields == "id"

      Calendar::CalendarListEntry.new(id: " Otto@LoopLabs.cc ", primary: true)
    end

    def list_calendar_lists(**options)
      @calendar_list_calls << options
      @calendar_pages.fetch(@calendar_list_calls.length - 1)
    end

    def list_events(calendar_id, **options)
      @event_calls << options.merge(calendar_id: calendar_id)
      @event_pages.fetch(@event_calls.length - 1)
    end

    def get_event(calendar_id, event_id, **options)
      @event_get_calls << options.merge(calendar_id:, event_id:)
      raise event_get_error if event_get_error

      @events.fetch(event_id)
    end

    def patch_event(calendar_id, event_id, event, **options)
      @event_patch_calls << options.merge(calendar_id:, event_id:, event:)
      @events.fetch(event_id).attendees = event.attendees
    end

    def delete_event(calendar_id, event_id, **options)
      @event_delete_calls << options.merge(calendar_id:, event_id:)
      raise delete_error if delete_error

      @events.fetch(event_id).status = "cancelled"
    end
  end

  test "returns only owned secondary calendars and normalizes the connected account" do
    service = FakeService.new(calendar_pages: [
      Calendar::CalendarList.new(
        items: [
          Calendar::CalendarListEntry.new(id: "otto@looplabs.cc", summary: "Primary", primary: true, access_role: "owner"),
          Calendar::CalendarListEntry.new(
            id: "sessions@group.calendar.google.com",
            summary: "Old name",
            summary_override: "Rails.Builders Sessions",
            time_zone: "Europe/Madrid",
            data_owner: "OTTO@LOOPLABS.CC",
            access_role: "owner"
          ),
          Calendar::CalendarListEntry.new(
            id: "shared@group.calendar.google.com",
            summary: "Shared",
            data_owner: "someone@example.com",
            access_role: "owner"
          )
        ],
        next_page_token: "next-page"
      ),
      Calendar::CalendarList.new(
        items: [
          Calendar::CalendarListEntry.new(
            id: "deleted@group.calendar.google.com",
            summary: "Deleted",
            data_owner: "otto@looplabs.cc",
            access_role: "owner",
            deleted: true
          )
        ]
      )
    ])
    client = GoogleWorkspace::CalendarClient.new(connection: Object.new, service: service)

    assert_equal "otto@looplabs.cc", client.account_email
    assert_equal [ {
      id: "sessions@group.calendar.google.com",
      name: "Rails.Builders Sessions",
      time_zone: "Europe/Madrid",
      data_owner: "otto@looplabs.cc"
    } ], client.owned_secondary_calendars
    assert_equal [ nil, "next-page" ], service.calendar_list_calls.map { |call| call[:page_token] }
    assert service.calendar_list_calls.all? { |call| call[:min_access_role] == "owner" }
  end

  test "expands timed recurring events across every page and safely extracts Google Meet links" do
    starts_at = Time.utc(2026, 8, 20)
    ends_at = Time.utc(2026, 12, 18)
    meet_data = Calendar::ConferenceData.new(
      conference_solution: Calendar::ConferenceSolution.new(
        key: Calendar::ConferenceSolutionKey.new(type: "hangoutsMeet")
      ),
      entry_points: [ Calendar::EntryPoint.new(entry_point_type: "video", uri: "https://meet.google.com/abc-defg-hij") ]
    )
    service = FakeService.new(event_pages: [
      Calendar::Events.new(
        time_zone: "Europe/Madrid",
        next_page_token: "next-page",
        items: [
          Calendar::Event.new(
            id: "recurring-instance-1",
            status: "confirmed",
            summary: "Builder Clinic",
            description: "Bring a blocker.",
            location: "Online",
            conference_data: meet_data,
            start: Calendar::EventDateTime.new(date_time: DateTime.iso8601("2026-09-08T18:00:00+02:00")),
            end: Calendar::EventDateTime.new(date_time: DateTime.iso8601("2026-09-08T19:00:00+02:00"))
          ),
          Calendar::Event.new(
            id: "all-day",
            status: "confirmed",
            start: Calendar::EventDateTime.new(date: Date.new(2026, 9, 9)),
            end: Calendar::EventDateTime.new(date: Date.new(2026, 9, 10))
          )
        ]
      ),
      Calendar::Events.new(items: [ Calendar::Event.new(id: "cancelled", status: "cancelled") ])
    ])
    client = GoogleWorkspace::CalendarClient.new(connection: Object.new, service: service)

    events = client.list_events(
      calendar_id: "sessions@group.calendar.google.com",
      starts_at: starts_at,
      ends_at: ends_at
    )

    assert_equal [ "recurring-instance-1", "all-day", "cancelled" ], events.map { |event| event[:id] }
    assert_equal "https://meet.google.com/abc-defg-hij", events.first[:meet_url]
    assert_equal Time.iso8601("2026-09-08T16:00:00Z"), events.first[:starts_at]
    assert_equal "Europe/Madrid", events.first[:time_zone]
    assert events.second[:all_day]
    assert_equal({ id: "cancelled", status: "cancelled" }, events.third)
    assert_equal [ nil, "next-page" ], service.event_calls.map { |call| call[:page_token] }
    assert service.event_calls.all? { |call| call[:single_events] && call[:show_deleted] }
    assert service.event_calls.all? { |call| call[:time_min] == starts_at.iso8601 && call[:time_max] == ends_at.iso8601 }
    assert service.event_calls.all? { |call| call[:fields] == GoogleWorkspace::CalendarClient::EVENT_FIELDS }
  end

  test "adds an attendee once per upcoming event series and optionally notifies guests" do
    starts_at = Time.utc(2026, 9, 13)
    ends_at = Time.utc(2026, 12, 18)
    service = FakeService.new(
      event_pages: [
        Calendar::Events.new(items: [
          Calendar::Event.new(
            id: "series-instance-1",
            recurring_event_id: "series",
            status: "confirmed",
            start: Calendar::EventDateTime.new(date_time: starts_at + 1.day),
            end: Calendar::EventDateTime.new(date_time: starts_at + 1.day + 1.hour)
          ),
          Calendar::Event.new(
            id: "series-instance-2",
            recurring_event_id: "series",
            status: "confirmed",
            start: Calendar::EventDateTime.new(date_time: starts_at + 8.days),
            end: Calendar::EventDateTime.new(date_time: starts_at + 8.days + 1.hour)
          ),
          Calendar::Event.new(
            id: "already-invited",
            status: "confirmed",
            start: Calendar::EventDateTime.new(date_time: starts_at + 2.days),
            end: Calendar::EventDateTime.new(date_time: starts_at + 2.days + 1.hour)
          )
        ]),
        Calendar::Events.new(items: [])
      ],
      events: {
        "series" => Calendar::Event.new(
          etag: "series-v1",
          attendees: [ Calendar::EventAttendee.new(email: "facilitator@example.com", response_status: "accepted") ]
        ),
        "already-invited" => Calendar::Event.new(attendees: [ Calendar::EventAttendee.new(email: "BUILDER@example.com") ])
      }
    )
    client = GoogleWorkspace::CalendarClient.new(connection: Object.new, service: service)

    added = client.add_attendee_to_upcoming_events(
      calendar_id: "sessions@group.calendar.google.com",
      starts_at:,
      ends_at:,
      email: "builder@example.com",
      send_notification: true
    )

    assert_equal 1, added
    assert_equal %w[already-invited series], service.event_get_calls.map { |call| call[:event_id] }.sort
    assert service.event_get_calls.all? { |call| call[:fields] == "attendees,etag" }
    assert_equal 1, service.event_patch_calls.size
    patch = service.event_patch_calls.first
    assert_equal "series", patch[:event_id]
    assert_equal "all", patch[:send_updates]
    assert_equal({ "If-Match" => "series-v1" }, patch[:options].header)
    assert_equal %w[builder@example.com facilitator@example.com], patch[:event].attendees.map(&:email).sort
    assert_equal "accepted", patch[:event].attendees.find { |attendee| attendee.email == "facilitator@example.com" }.response_status
  end

  test "can add an attendee without sending guest notifications" do
    starts_at = Time.utc(2026, 9, 13)
    service = FakeService.new(
      event_pages: [ Calendar::Events.new(items: [
        Calendar::Event.new(
          id: "session",
          status: "confirmed",
          start: Calendar::EventDateTime.new(date_time: starts_at + 1.day),
          end: Calendar::EventDateTime.new(date_time: starts_at + 1.day + 1.hour)
        )
      ]), Calendar::Events.new(items: []) ],
      events: { "session" => Calendar::Event.new(etag: "session-v1") }
    )

    GoogleWorkspace::CalendarClient.new(connection: Object.new, service: service).add_attendee_to_upcoming_events(
      calendar_id: "sessions@group.calendar.google.com",
      starts_at:,
      ends_at: starts_at + 1.month,
      email: "builder@example.com",
      send_notification: false
    )

    assert_equal "none", service.event_patch_calls.first[:send_updates]
  end

  test "returns only attendees who explicitly declined an event" do
    service = FakeService.new(events: {
      "weekly-session" => Calendar::Event.new(attendees: [
        Calendar::EventAttendee.new(email: "DECLINED@example.com", response_status: "declined"),
        Calendar::EventAttendee.new(email: "accepted@example.com", response_status: "accepted"),
        Calendar::EventAttendee.new(email: "tentative@example.com", response_status: "tentative"),
        Calendar::EventAttendee.new(email: "neutral@example.com", response_status: "needsAction")
      ])
    })
    client = GoogleWorkspace::CalendarClient.new(connection: Object.new, service: service)

    assert_equal [ "declined@example.com" ], client.declined_attendee_emails(
      calendar_id: "sessions@group.calendar.google.com",
      event_id: "weekly-session"
    )
    assert_equal [ {
      calendar_id: "sessions@group.calendar.google.com",
      event_id: "weekly-session",
      fields: "attendees(email,responseStatus)"
    } ], service.event_get_calls
  end

  test "removing a Builder preserves other guests and handles recurring series and edited exceptions" do
    starts_at = Time.utc(2026, 10, 16)
    ends_at = Time.utc(2026, 12, 18)
    event = ->(id, series = nil) do
      Calendar::Event.new(id:, recurring_event_id: series, status: "confirmed",
        start: Calendar::EventDateTime.new(date_time: starts_at + 1.day),
        end: Calendar::EventDateTime.new(date_time: starts_at + 1.day + 1.hour))
    end
    guests = [ Calendar::EventAttendee.new(email: "BUILDER@example.com", response_status: "accepted"),
      Calendar::EventAttendee.new(email: "other@example.com", response_status: "tentative") ]
    service = FakeService.new(event_pages: [
      Calendar::Events.new(items: [ event.call("instance-1", "series"), event.call("instance-2", "series"), event.call("single"),
        Calendar::Event.new(id: "cancelled", status: "cancelled"),
        Calendar::Event.new(id: "all-day", start: Calendar::EventDateTime.new(date: starts_at.to_date)) ]),
      Calendar::Events.new(items: [ event.call("edited-instance", "series") ])
    ] * 2, events: {
      "series" => Calendar::Event.new(etag: "series-v1", attendees: guests),
      "single" => Calendar::Event.new(etag: "single-v1", attendees: guests),
      "edited-instance" => Calendar::Event.new(etag: "exception-v1", attendees: guests)
    })

    removed = GoogleWorkspace::CalendarClient.new(connection: Object.new, service: service).remove_attendee_from_upcoming_events(
      calendar_id: "sessions@group.calendar.google.com", starts_at:, ends_at:, email: "builder@example.com")

    assert_equal 3, removed
    assert_equal [ "series", "single", "edited-instance" ], service.event_patch_calls.map { |call| call[:event_id] }
    service.event_patch_calls.each do |call|
      assert_equal [ "other@example.com" ], call[:event].attendees.map(&:email)
      assert_equal "tentative", call[:event].attendees.sole.response_status
      assert_equal "none", call[:send_updates]
      assert call[:options].header.key?("If-Match")
    end
    restored = GoogleWorkspace::CalendarClient.new(connection: Object.new, service: service).add_attendee_to_upcoming_events(
      calendar_id: "sessions@group.calendar.google.com", starts_at:, ends_at:, email: "builder@example.com", send_notification: false)
    assert_equal 3, restored
    assert_equal [ "series", "single", "edited-instance" ], service.event_patch_calls.last(3).map { |call| call[:event_id] }
    service.event_patch_calls.last(3).each do |call|
      assert_equal %w[builder@example.com other@example.com], call[:event].attendees.map(&:email).sort
    end
  end

  test "removing a guest who is already absent makes no Calendar change" do
    starts_at = Time.utc(2026, 10, 16)
    service = FakeService.new(event_pages: [
      Calendar::Events.new(items: [ Calendar::Event.new(id: "single", status: "confirmed",
        start: Calendar::EventDateTime.new(date_time: starts_at + 1.day), end: Calendar::EventDateTime.new(date_time: starts_at + 1.day + 1.hour)) ]),
      Calendar::Events.new(items: [])
    ], events: { "single" => Calendar::Event.new(attendees: [ Calendar::EventAttendee.new(email: "other@example.com") ]) })

    assert_equal 0, GoogleWorkspace::CalendarClient.new(connection: Object.new, service: service).remove_attendee_from_upcoming_events(
      calendar_id: "sessions@group.calendar.google.com", starts_at:, ends_at: starts_at + 1.month, email: "builder@example.com")
    assert_empty service.event_patch_calls
  end

  test "refuses to delete a recurring master even when a stale session still holds its old one-off id" do
    service = FakeService.new(events: {
      "formerly-single" => Calendar::Event.new(status: "confirmed", recurrence: [ "RRULE:FREQ=WEEKLY" ], etag: '"new-series-version"')
    })
    connection = Struct.new(:google_calendar_id).new("sessions@group.calendar.google.com")
    client = GoogleWorkspace::CalendarClient.new(connection:, service:)

    assert_raises(GoogleWorkspace::CalendarClient::UnsafeEventDeletion) { client.delete_event(event_id: "formerly-single") }
    assert_empty service.event_delete_calls
    assert_equal "confirmed", service.get_event(connection.google_calendar_id, "formerly-single").status
  end

  test "deletes only the supplied recurring occurrence and notifies every guest" do
    service = FakeService.new(events: {
      "series" => Calendar::Event.new(status: "confirmed"),
      "series_20261022T153000Z" => Calendar::Event.new(recurring_event_id: "series", status: "confirmed", etag: '"occurrence-version"'),
      "series_20261029T163000Z" => Calendar::Event.new(recurring_event_id: "series", status: "confirmed")
    })
    connection = Struct.new(:google_calendar_id).new("sessions@group.calendar.google.com")
    client = GoogleWorkspace::CalendarClient.new(connection:, service:)

    assert client.delete_event(event_id: "series_20261022T153000Z")

    assert_equal [ {
      calendar_id: connection.google_calendar_id,
      event_id: "series_20261022T153000Z",
      send_updates: "all"
    } ], service.event_delete_calls.map { |call| call.except(:options) }
    assert_equal({ "If-Match" => '"occurrence-version"' }, service.event_delete_calls.first[:options].header)
    assert_equal [ {
      calendar_id: connection.google_calendar_id, event_id: "series_20261022T153000Z", fields: "status,recurrence,etag"
    } ], service.event_get_calls
    assert_equal "cancelled", service.get_event(connection.google_calendar_id, "series_20261022T153000Z").status
    assert_equal "confirmed", service.get_event(connection.google_calendar_id, "series").status
    assert_equal "confirmed", service.get_event(connection.google_calendar_id, "series_20261029T163000Z").status
    assert_empty service.event_calls
  end

  test "already deleted events are idempotent while 404 requires retained calendar ownership" do
    connection = Struct.new(:google_calendar_id).new("sessions@group.calendar.google.com")
    service = FakeService.new(events: { "deleted-occurrence" => Calendar::Event.new(status: "confirmed", etag: '"version"') })
    client = GoogleWorkspace::CalendarClient.new(connection:, service:)
    service.delete_error = Google::Apis::ClientError.new("Resource has been deleted", status_code: 410)

    assert client.delete_event(event_id: "deleted-occurrence")
    assert_empty service.calendar_get_calls

    service.delete_error = Google::Apis::ClientError.new("Not Found", status_code: 404)
    assert client.delete_event(event_id: "deleted-occurrence")
    assert_equal [ { calendar_id: connection.google_calendar_id, fields: "id,accessRole" } ], service.calendar_get_calls

    service.calendar_access_role = "reader"
    assert_raises(Google::Apis::ClientError) { client.delete_event(event_id: "deleted-occurrence") }
    service.calendar_error = Google::Apis::ClientError.new("Calendar unavailable", status_code: 404)
    assert_raises(Google::Apis::ClientError) { client.delete_event(event_id: "deleted-occurrence") }
  end

  test "a missing preflight event still requires ownership and a cancelled one needs no deletion" do
    connection = Struct.new(:google_calendar_id).new("sessions@group.calendar.google.com")
    service = FakeService.new(events: { "cancelled" => Calendar::Event.new(status: "cancelled") })
    client = GoogleWorkspace::CalendarClient.new(connection:, service:)
    assert client.delete_event(event_id: "cancelled")
    assert_empty service.event_delete_calls

    service.event_get_error = Google::Apis::ClientError.new("Not Found", status_code: 404)
    assert client.delete_event(event_id: "missing")
    service.calendar_access_role = "reader"
    assert_raises(Google::Apis::ClientError) { client.delete_event(event_id: "missing") }
    assert_empty service.event_delete_calls
  end

  test "an event changed into a series after preflight fails the conditional deletion" do
    event = Calendar::Event.new(status: "confirmed", etag: '"single-version"')
    service = FakeService.new(events: { "single" => event })
    service.define_singleton_method(:delete_event) do |calendar_id, event_id, **options|
      event.recurrence = [ "RRULE:FREQ=WEEKLY" ]
      event.etag = '"series-version"'
      unless options[:options].header["If-Match"] == event.etag
        raise Google::Apis::ClientError.new("Precondition Failed", status_code: 412)
      end
      event.status = "cancelled"
    end
    connection = Struct.new(:google_calendar_id).new("sessions@group.calendar.google.com")
    client = GoogleWorkspace::CalendarClient.new(connection:, service:)

    assert_equal 412, assert_raises(Google::Apis::ClientError) { client.delete_event(event_id: "single") }.status_code
    assert_equal "confirmed", event.status
    assert_raises(GoogleWorkspace::CalendarClient::UnsafeEventDeletion) { client.delete_event(event_id: "single") }
  end

  test "refuses unversioned deletions" do
    service = FakeService.new(events: { "single" => Calendar::Event.new(status: "confirmed") })
    connection = Struct.new(:google_calendar_id).new("sessions@group.calendar.google.com")
    client = GoogleWorkspace::CalendarClient.new(connection:, service:)

    assert_raises(GoogleWorkspace::CalendarClient::UnsafeEventDeletion) { client.delete_event(event_id: "single") }
    assert_empty service.event_delete_calls
  end

  test "deletion propagates authorization rate limit and server failures" do
    connection = Struct.new(:google_calendar_id).new("sessions@group.calendar.google.com")
    service = FakeService.new(events: { "occurrence" => Calendar::Event.new(status: "confirmed", etag: '"version"') })
    client = GoogleWorkspace::CalendarClient.new(connection:, service:)
    [
      Google::Apis::AuthorizationError.new("Unauthorized", status_code: 401),
      Google::Apis::ClientError.new("Forbidden", status_code: 403),
      Google::Apis::ClientError.new("Rate limited", status_code: 429),
      Google::Apis::ServerError.new("Backend Error", status_code: 500)
    ].each do |error|
      service.delete_error = error
      assert_same error, assert_raises(error.class) { client.delete_event(event_id: "occurrence") }
    end
    assert_empty service.calendar_get_calls
  end
end
