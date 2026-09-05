import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["display", "total"]
  static values = {
    seconds: Number,
    totalSeconds: Number,
    renderedAt: Number,
    mode: String,
    paused: Boolean,
    heartbeatUrl: String,
    version: String,
    state: String
  }

  connect() {
    this.tick()
    this.tickTimer = setInterval(() => this.tick(), 200)
    this.heartbeatTimer = setInterval(() => this.heartbeat(), 3000)
  }

  disconnect() {
    clearInterval(this.tickTimer)
    clearInterval(this.heartbeatTimer)
  }

  tick() {
    const elapsed = this.pausedValue ? 0 : (Date.now() - this.renderedAtValue) / 1000
    const raw = this.modeValue === "countup" ? this.secondsValue + elapsed : this.secondsValue - elapsed
    const seconds = this.modeValue === "countup" ? Math.max(0, Math.floor(raw)) : Math.ceil(raw)
    this.displayTarget.textContent = this.format(seconds)
    if (this.hasTotalTarget) this.totalTarget.textContent = this.format(Math.max(0, Math.ceil(this.totalSecondsValue - elapsed)))
    this.element.classList.toggle("timer-amber", this.modeValue === "countdown" && seconds <= 30 && seconds > 10)
    this.element.classList.toggle("timer-red", this.modeValue === "countdown" && seconds <= 10)
  }

  async heartbeat() {
    const token = document.querySelector("meta[name='csrf-token']")?.content
    const response = await fetch(this.heartbeatUrlValue, {
      method: "PATCH",
      headers: { "Accept": "application/json", "X-CSRF-Token": token },
      credentials: "same-origin"
    }).catch(() => null)
    if (!response?.ok) return

    const state = await response.json()
    if (document.querySelector("[data-speaker-order-saving='true']")) return
    if (state.version < this.versionValue) return
    if (state.version !== this.versionValue || state.state !== this.stateValue || state.paused !== this.pausedValue) {
      window.Turbo.visit(window.location.href, { action: "replace" })
    }
  }

  format(totalSeconds) {
    const sign = totalSeconds < 0 ? "−" : ""
    const absolute = Math.abs(totalSeconds)
    const minutes = Math.floor(absolute / 60)
    const seconds = absolute % 60
    return `${sign}${minutes}:${seconds.toString().padStart(2, "0")}`
  }
}
