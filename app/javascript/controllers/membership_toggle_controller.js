import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["choice", "dialog"]

  connect() {
    this.savedChoice = this.choiceTarget.checked
  }

  confirm() {
    if (this.restoring) {
      this.restoring = false
      return
    }

    this.dialogTarget.showModal()
  }

  accept(event) {
    event.currentTarget.disabled = true
    this.dialogTarget.close()
    this.element.requestSubmit()
  }

  cancel(event) {
    event.preventDefault()
    this.dialogTarget.close()
    this.restoring = true
    this.choiceTarget.checked = this.savedChoice
    this.choiceTarget.dispatchEvent(new Event("change", { bubbles: true }))
  }
}
