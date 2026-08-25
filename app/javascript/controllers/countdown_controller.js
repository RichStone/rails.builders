import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["days", "hours", "minutes", "seconds", "label", "accessible"]
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
    const days = Math.floor(remaining / 86400000).toString().padStart(2, "0")
    const hours = Math.floor(remaining / 3600000 % 24).toString().padStart(2, "0")
    const minutes = Math.floor(remaining / 60000 % 60).toString().padStart(2, "0")
    const seconds = Math.floor(remaining / 1000 % 60).toString().padStart(2, "0")
    const label = now < start ? "until the new cohort begins" : now < finish ? "until current cohort ends" : "the cohort has ended"
    this.turn(this.daysTarget, days)
    this.turn(this.hoursTarget, hours)
    this.turn(this.minutesTarget, minutes)
    this.turn(this.secondsTarget, seconds)
    this.labelTarget.textContent = label
    this.accessibleTarget.textContent = `${Number(days)} days, ${Number(hours)} hours, ${Number(minutes)} minutes, ${Number(seconds)} seconds ${label}`
  }

  turn(target, value) {
    if (target.dataset.value === value) return

    target.dataset.previous = target.dataset.value
    target.dataset.value = value
    target.textContent = value
    target.classList.remove("is-turning")
    void target.offsetWidth
    target.classList.add("is-turning")
  }
}
