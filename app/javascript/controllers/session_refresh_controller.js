import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = { url: String, version: String }

  connect() {
    this.refreshTimer = setInterval(() => this.check(), 10000)
  }

  disconnect() {
    clearInterval(this.refreshTimer)
  }

  async check() {
    const response = await fetch(this.urlValue, {
      method: "PATCH",
      headers: {
        "Accept": "application/json",
        "X-CSRF-Token": document.querySelector("meta[name='csrf-token']")?.content
      },
      credentials: "same-origin"
    }).catch(() => null)
    if (!this.element.isConnected) return
    if (response?.status === 422 || response?.redirected) {
      this.disconnect()
      window.location.reload()
      return
    }
    if (!response?.ok) return

    const state = await response.json()
    if (!this.element.isConnected) return
    if (state.version !== this.versionValue) window.Turbo.visit(window.location.href, { action: "replace" })
  }
}
