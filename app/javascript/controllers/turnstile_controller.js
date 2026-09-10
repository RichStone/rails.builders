import { Controller } from "@hotwired/stimulus"

let scriptLoad

function loadTurnstile() {
  if (window.turnstile) return new Promise((resolve) => window.turnstile.ready(resolve))
  return scriptLoad ||= new Promise((resolve, reject) => {
    const script = document.createElement("script")
    script.src = "https://challenges.cloudflare.com/turnstile/v0/api.js?render=explicit"
    script.async = true
    script.nonce = document.querySelector("meta[name='csp-nonce']")?.content || ""
    const failed = () => {
      clearTimeout(timeout)
      script.remove()
      scriptLoad = undefined
      reject(new Error("Browser verification could not load"))
    }
    const timeout = setTimeout(failed, 10000)
    script.onerror = failed
    script.onload = () => {
      clearTimeout(timeout)
      if (window.turnstile) window.turnstile.ready(resolve)
      else failed()
    }
    document.head.append(script)
  })
}

export default class extends Controller {
  static targets = ["widget", "status", "retry", "submit"]
  static values = { siteKey: String }

  async connect() {
    const connection = this.connection = Symbol()
    this.state(false, "Checking your browser…")
    try {
      await loadTurnstile()
      if (this.connection !== connection || !this.element.isConnected) return
      this.widgetId = window.turnstile.render(this.widgetTarget, {
        sitekey: this.siteKeyValue,
        action: "sign_in",
        theme: "auto",
        size: "compact",
        retry: "never",
        "refresh-expired": "manual",
        callback: () => this.state(true, "Browser verified."),
        "error-callback": () => { this.failed(); return true },
        "timeout-callback": () => this.failed(),
        "expired-callback": () => this.retry()
      })
    } catch {
      if (this.connection === connection) this.failed()
    }
  }

  disconnect() {
    this.connection = undefined
    if (this.widgetId !== undefined) window.turnstile?.remove(this.widgetId)
    this.widgetId = undefined
  }

  beforeCache() {
    this.disconnect()
    this.state(false, "Checking your browser…")
  }

  submitted(event) {
    if (!event.detail.success && this.element.isConnected) this.retry()
  }

  retry() {
    if (this.widgetId === undefined) return this.connect()
    this.state(false, "Checking your browser…")
    window.turnstile.reset(this.widgetId)
  }

  failed() {
    this.state(false, "Browser verification failed. Please retry or reload this page.", true)
  }

  state(verified, message, retry = false) {
    this.submitTarget.disabled = !verified
    this.statusTarget.textContent = message
    this.retryTarget.hidden = !retry
  }
}
