require "test_helper"

class GoogleWorkspace::CalendarClientTest < ActiveSupport::TestCase
  Calendar = Google::Apis::CalendarV3

  class FakeService
    attr_reader :calendar_list_calls, :event_calls, :event_get_calls, :event_patch_calls

    def initialize(calendar_pages: [], event_pages: [], events: {})
      @calendar_pages = calendar_pages
      @event_pages = event_pages
      @events = events
      @calendar_list_calls = []
      @event_calls = []
      @event_get_calls = []
      @event_patch_calls = []
    end

    def get_calendar_list(calendar_id, fields:)
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
      @events.fetch(event_id)
    end

    def patch_event(calendar_id, event_id, event, **options)
      @event_patch_calls << options.merge(calendar_id:, event_id:, event:)
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
        ])
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
      ]) ],
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
end
