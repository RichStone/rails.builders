require "google/apis/core/base_service"
require "json"
require "uri"

module GoogleWorkspace
  class NotesClient
    AuthorizationRequired = Class.new(StandardError)

    # Use the existing Google API transport for refresh, retries and API errors.
    class DocsService < Google::Apis::Core::BaseService
      def initialize
        super("https://docs.googleapis.com/", "v1/", client_name: "Rails.Builders")
      end

      def get_document(document_id)
        command = make_simple_command(:get, "documents/{documentId}", nil)
        command.params["documentId"] = document_id
        command.query["includeTabsContent"] = true
        JSON.parse(execute_or_queue_command(command))
      end
    end

    def initialize(connection:, calendar_client: nil, service: nil)
      @connection = connection
      @calendar_client = calendar_client || CalendarClient.new(connection: connection)
      @service = service
    end

    def notes_for(builder_session)
      documents = calendar_client.notes_attachments(builder_session).filter_map do |attachment|
        document = service.get_document(attachment.fetch(:id))
        source_url = "https://docs.google.com/document/d/#{attachment.fetch(:id)}/edit"
        title = document["title"].presence || attachment.fetch(:title)
        tabs = Array(document["tabs"])
        tabs = [ { "documentTab" => document } ] if tabs.empty?
        rendered, meaningful = render_tabs(tabs, source_url, title)
        next unless meaningful

        "# #{escape(title)}\n\n[Open source document](#{source_url})\n\n#{rendered}"
      end
      documents.join("\n\n---\n\n").presence
    end

    private

    attr_reader :connection, :calendar_client

    def service
      @service ||= begin
        credentials = Authorization.new(connection: connection).notes_credentials
        raise AuthorizationRequired, "Reconnect Google Calendar to allow reading attached notes" unless credentials

        DocsService.new.tap do |client|
          client.authorization = credentials
          client.client_options.application_name = "Rails.Builders"
          client.client_options.open_timeout_sec = 5
          client.client_options.read_timeout_sec = 20
          client.client_options.send_timeout_sec = 20
          client.client_options.log_http_requests = false
          client.request_options.retries = 3
          client.request_options.max_elapsed_time = 30
        end
      end
    end

    def render_tabs(tabs, source_url, document_title)
      meaningful = false
      rendered = tabs.map do |tab|
        document_tab = tab.fetch("documentTab", {})
        content, has_notes = render_elements(document_tab.dig("body", "content"), source_url, document_title)
        meaningful ||= has_notes
        title = tab.dig("tabProperties", "title")
        parts = []
        parts << "## #{escape(title)}" if title.present?
        parts << content if content.present?
        %w[headers footers footnotes].each do |collection|
          document_tab.fetch(collection, {}).each_value do |section|
            text, has_notes = render_elements(section["content"], source_url, document_title)
            meaningful ||= has_notes
            parts << text if text.present?
          end
        end
        children, has_notes = render_tabs(Array(tab["childTabs"]), source_url, document_title)
        meaningful ||= has_notes
        parts << children if children.present?
        parts.join("\n\n")
      end
      [ rendered.reject(&:blank?).join("\n\n"), meaningful ]
    end

    def render_elements(elements, source_url, document_title)
      meaningful = false
      rendered = Array(elements).map do |element|
        if (paragraph = element["paragraph"])
          text = Array(paragraph["elements"]).map { |item| render_inline(item, source_url) }.join.strip
          has_image = Array(paragraph["elements"]).any? { |item| item.key?("inlineObjectElement") } || paragraph["positionedObjectIds"].present?
          text += "\n\n#{image_placeholder(source_url)}" if paragraph["positionedObjectIds"].present?
          plain_text = Array(paragraph["elements"]).filter_map { |item| item.dig("textRun", "content") || item.dig("richLink", "richLinkProperties", "title") }.join
          meaningful ||= has_image || meaningful_paragraph?(plain_text, document_title)
          style = paragraph.dig("paragraphStyle", "namedStyleType").to_s
          level = style.delete_prefix("HEADING_").to_i if style.start_with?("HEADING_")
          text = "#{'#' * (level + 2).clamp(3, 6)} #{text}" if level && text.present?
          text = "- #{text}" if paragraph["bullet"] && text.present?
          text
        elsif (table = element["table"])
          Array(table["tableRows"]).map do |row|
            Array(row["tableCells"]).map do |cell|
              text, has_notes = render_elements(cell["content"], source_url, document_title)
              meaningful ||= has_notes
              text
            end.reject(&:blank?).join("\n\n")
          end.join("\n\n")
        elsif (contents = element["tableOfContents"])
          text, = render_elements(contents["content"], source_url, document_title)
          text
        end
      end
      [ rendered.compact.reject(&:blank?).join("\n\n"), meaningful ]
    end

    def render_inline(item, source_url)
      if (run = item["textRun"])
        text = escape(run.fetch("content", ""))
        link(text, run.dig("textStyle", "link", "url"))
      elsif (properties = item.dig("richLink", "richLinkProperties"))
        link(escape(properties["title"]), properties["uri"])
      elsif (properties = item.dig("person", "personProperties"))
        escape(properties["name"].presence || properties["email"])
      elsif item["inlineObjectElement"]
        image_placeholder(source_url)
      else
        ""
      end
    end

    def meaningful_paragraph?(text, document_title)
      text = text.strip
      return false if text == document_title || text.match?(/\A(?:attendees|participants)\s*:/i)
      return false if text.match?(/\A(?:notes|meeting notes|agenda|action items|summary|details|detailed notes|suggested next steps)\s*:?\z/i)

      text.match?(/[[:alnum:]]/)
    end

    def image_placeholder(source_url)
      "[Image — open source document](#{source_url})"
    end

    def escape(value)
      value.to_s.gsub(/([\\`*_\[\]<>#|])/) { |character| "\\#{character}" }
    end

    def link(text, url)
      uri = URI.parse(url.to_s)
      return text unless uri.is_a?(URI::HTTP) && uri.host.present? && !url.match?(/[<>\s]/)

      "[#{text}](<#{url}>)"
    rescue URI::InvalidURIError
      text
    end
  end
end
