import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["trigger"]

  connect() {
    this.sync()
  }

  sync() {
    this.triggerTarget.setAttribute("aria-expanded", this.element.open.toString())
  }

  openOnHover(event) {
    if (event.pointerType !== "mouse" || this.element.open) return

    this.openedByHover = true
    this.element.open = true
  }

  closeAfterHover() {
    if (!this.openedByHover) return

    this.openedByHover = false
    this.element.open = false
  }

  close(event) {
    if (!this.element.open) return

    event.preventDefault()
    this.openedByHover = false
    this.element.open = false
    this.sync()

    if (event.type === "click") this.triggerTarget.focus()
  }
}
