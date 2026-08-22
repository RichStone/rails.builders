import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["item", "status"]
  static values = { url: String }

  start(event) {
    this.draggedItem = event.currentTarget.closest("[data-speaker-order-target='item']")
    event.dataTransfer.effectAllowed = "move"
    event.dataTransfer.setData("text/plain", this.draggedItem.dataset.attendanceId)
  }

  over(event) {
    if (!this.draggedItem) return

    const target = event.target.closest("[data-speaker-order-target='item']")
    if (!target || target === this.draggedItem) return

    event.preventDefault()
    const afterTarget = event.clientY >= target.getBoundingClientRect().top + target.offsetHeight / 2
    target.parentNode.insertBefore(this.draggedItem, afterTarget ? target.nextSibling : target)
  }

  drop(event) {
    if (!this.draggedItem) return

    event.preventDefault()
    this.persist()
  }

  end() {
    this.draggedItem = null
  }

  earlier(event) {
    const item = event.currentTarget.closest("[data-speaker-order-target='item']")
    const items = this.itemTargets
    const index = items.indexOf(item)
    if (index <= 0) return

    item.parentNode.insertBefore(item, items[index - 1])
    this.persist()
  }

  later(event) {
    const item = event.currentTarget.closest("[data-speaker-order-target='item']")
    const items = this.itemTargets
    const index = items.indexOf(item)
    if (index < 0 || index >= items.length - 1) return

    item.parentNode.insertBefore(items[index + 1], item)
    this.persist()
  }

  async persist() {
    const response = await fetch(this.urlValue, {
      method: "PATCH",
      headers: {
        "Accept": "application/json",
        "Content-Type": "application/json",
        "X-CSRF-Token": document.querySelector("meta[name='csrf-token']")?.content
      },
      credentials: "same-origin",
      body: JSON.stringify({ attendance_ids: this.itemTargets.map((item) => item.dataset.attendanceId) })
    }).catch(() => null)

    if (response?.status === 204) {
      if (this.hasStatusTarget) this.statusTarget.textContent = "Speaker order saved."
    } else {
      if (this.hasStatusTarget) this.statusTarget.textContent = "Speaker order changed elsewhere. Reloading."
      window.Turbo.visit(window.location.href, { action: "replace" })
    }
  }
}
