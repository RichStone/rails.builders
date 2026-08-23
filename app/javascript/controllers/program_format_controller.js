import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["play", "item", "progress", "handshake"]

  connect() { this.timers = [] }
  disconnect() { this.timers.forEach(clearTimeout) }

  start() {
    if (this.element.classList.contains("is-running")) return

    this.element.classList.add("is-running")
    this.playTarget.disabled = true
    this.progressTarget.hidden = false

    this.itemTargets.forEach((item, index) => {
      this.timers.push(setTimeout(() => {
        item.hidden = false
        item.classList.add("is-revealed")
        const progress = this.itemTargets.length === 1 ? 100 : index / (this.itemTargets.length - 1) * 100
        this.progressTarget.style.setProperty("--format-progress", `${progress}%`)

        if (index === this.itemTargets.length - 1) {
          this.timers.push(setTimeout(() => { this.handshakeTarget.hidden = false }, 500))
        }
      }, index * 2000))
    })
  }
}
