import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["days", "hours", "minutes", "seconds", "label"]
  static values = { start: String, finish: String }

  connect() {
    this.tick()
    this.timer = setInterval(() => this.tick(), 1000)
  }

  disconnect() { clearInterval(this.timer) }

  tick() {
    const now = new Date()
    const start = new Date(`${this.startValue}T00:00:00`)
    const finish = new Date(`${this.finishValue}T23:59:59`)
    const target = now < start ? start : finish
    const remaining = Math.max(0, target - now)
    this.daysTarget.textContent = Math.floor(remaining / 86400000).toString().padStart(2, "0")
    this.hoursTarget.textContent = Math.floor(remaining / 3600000 % 24).toString().padStart(2, "0")
    this.minutesTarget.textContent = Math.floor(remaining / 60000 % 60).toString().padStart(2, "0")
    this.secondsTarget.textContent = Math.floor(remaining / 1000 % 60).toString().padStart(2, "0")
    this.labelTarget.textContent = now < start ? "until the new cohort begins" : now < finish ? "until current cohort ends" : "the cohort has ended"
  }
}
