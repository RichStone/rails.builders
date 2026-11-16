class WeeklyCherryMailer < ApplicationMailer
  def edition
    @copy = params.fetch(:copy)
    if params.fetch(:summary)
      mail(**edition_headers)
    else
      attachments.inline["weekly-builders-cherry.jpg"] = Rails.root.join("app/assets/images/weekly-builders-cherry.jpg").binread
      attachments["weekly-builders-cherry.jpg"].content_id = "weekly-cherry"
      mail(**edition_headers) do |format|
        format.text { render plain: @copy.fetch("text") }
        format.html { render html: @copy.fetch("html").html_safe, layout: false }
      end
    end
  end

  private

  def edition_headers
    {
      to: @copy.fetch("to"), subject: @copy.fetch("subject"), reply_to: "rich@looplabs.cc",
      options: { idempotency_key: "weekly-cherry-#{params.fetch(:delivery_id)}" }
    }
  end
end
