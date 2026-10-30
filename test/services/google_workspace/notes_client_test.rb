require "test_helper"

class GoogleWorkspace::NotesClientTest < ActiveSupport::TestCase
  class FakeCalendarClient
    def initialize(attachments)
      @attachments = attachments
    end

    def notes_attachments(_session)
      @attachments
    end
  end

  class FakeDocsService
    attr_reader :requested_ids

    def initialize(documents)
      @documents = documents
      @requested_ids = []
    end

    def get_document(id)
      requested_ids << id
      @documents.fetch(id)
    end
  end

  test "retrieves all document tabs through the authenticated Google API transport" do
    service = GoogleWorkspace::NotesClient::DocsService.new
    command = nil
    with_stubbed_singleton_method(service, :execute_or_queue_command, ->(request) { command = request; '{"tabs":[]}' }) do
      assert_equal({ "tabs" => [] }, service.get_document("meeting-notes"))
    end

    assert_equal "meeting-notes", command.params["documentId"]
    assert_equal true, command.query["includeTabsContent"]
    assert_equal "https://docs.googleapis.com/v1/documents/{documentId}", command.url.pattern
  end

  test "retains nested tabs table text links and image source references without signed image URLs" do
    document = {
      "title" => "Builder notes",
      "tabs" => [ {
        "tabProperties" => { "title" => "Summary" },
        "documentTab" => { "body" => { "content" => [ paragraph("A useful update.") ] } },
        "childTabs" => [ {
          "tabProperties" => { "title" => "Detailed notes" },
          "documentTab" => {
            "body" => { "content" => [
              { "table" => { "tableRows" => [ { "tableCells" => [ { "content" => [ paragraph("Table insight.") ] } ] } ] } },
              { "paragraph" => { "elements" => [ { "textRun" => { "content" => "Helpful site", "textStyle" => { "link" => { "url" => "https://example.com/resource?q=one" } } } } ] } },
              { "paragraph" => { "elements" => [ { "richLink" => { "richLinkProperties" => { "title" => "Related document", "uri" => "https://docs.google.com/document/d/related/edit" } } } ] } },
              { "paragraph" => { "elements" => [ { "inlineObjectElement" => { "inlineObjectId" => "image-1" } } ] } }
            ] },
            "inlineObjects" => { "image-1" => { "inlineObjectProperties" => { "embeddedObject" => { "imageProperties" => { "contentUri" => "https://private.example/signed-secret" } } } } },
            "footnotes" => { "footnote" => { "content" => [ paragraph("Footnote detail.") ] } }
          }
        } ]
      } ]
    }
    service = FakeDocsService.new("notes" => document)
    client = build_client(service: service)

    notes = client.notes_for(Object.new)

    [ "A useful update.", "Detailed notes", "Table insight.", "Footnote detail.", "[Helpful site](<https://example.com/resource?q=one>)",
      "[Related document](<https://docs.google.com/document/d/related/edit>)", "[Image — open source document](https://docs.google.com/document/d/notes/edit)" ].each do |text|
      assert_includes notes, text
    end
    assert_not_includes notes, "signed-secret"
    assert_equal [ "notes" ], service.requested_ids
  end

  test "returns no notes for an empty attached template but preserves real notes beside it" do
    template = { "title" => "Notes - Builders", "tabs" => [ { "documentTab" => { "body" => { "content" => [
      paragraph(" | \n"), paragraph("Attendees: \n"), paragraph("Notes\n"), paragraph("Action items\n")
    ] } } } ] }
    service = FakeDocsService.new("template" => template, "notes" => { "title" => "Notes by Gemini", "body" => { "content" => [ paragraph("Ship the small prototype.") ] } })
    client = build_client(service: service, attachments: [ { id: "template", title: "Notes - Builders" } ])
    assert_nil client.notes_for(Object.new)

    client = build_client(service: service, attachments: [ { id: "template", title: "Notes - Builders" }, { id: "notes", title: "Notes by Gemini" } ])
    notes = client.notes_for(Object.new)
    assert_includes notes, "Ship the small prototype."
    assert_not_includes notes, "Notes - Builders"
  end

  test "a missing document grant needs notes-specific reauthorization without changing Calendar connection state" do
    connection = Struct.new(:status).new("connected")
    authorizer = Object.new
    authorizer.define_singleton_method(:notes_credentials) { nil }
    client = GoogleWorkspace::NotesClient.new(connection: connection, calendar_client: FakeCalendarClient.new([ { id: "notes", title: "Notes" } ]))

    with_stubbed_singleton_method(GoogleWorkspace::Authorization, :new, authorizer) do
      assert_raises(GoogleWorkspace::NotesClient::AuthorizationRequired) { client.notes_for(Object.new) }
    end
    assert_equal "connected", connection.status
  end

  test "no attachments returns no notes without requiring a Docs grant" do
    client = GoogleWorkspace::NotesClient.new(connection: Object.new, calendar_client: FakeCalendarClient.new([]))
    assert_nil client.notes_for(Object.new)
  end

  test "unsafe hyperlinks remain readable text without executable URLs" do
    document = { "body" => { "content" => [ {
      "paragraph" => { "elements" => [ { "textRun" => { "content" => "Useful notes", "textStyle" => { "link" => { "url" => "javascript:alert(1)" } } } } ] }
    } ] } }
    notes = build_client(service: FakeDocsService.new("notes" => document)).notes_for(Object.new)
    assert_includes notes, "Useful notes"
    assert_not_includes notes, "javascript"
  end

  private

  def paragraph(text)
    { "paragraph" => { "elements" => [ { "textRun" => { "content" => text } } ] } }
  end

  def build_client(service:, attachments: [ { id: "notes", title: "Notes" } ])
    GoogleWorkspace::NotesClient.new(connection: Object.new, calendar_client: FakeCalendarClient.new(attachments), service: service)
  end
end
