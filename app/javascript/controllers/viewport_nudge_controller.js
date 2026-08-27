import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["item"]

  connect() {
    this.observer = new IntersectionObserver(entries => {
      entries.forEach(entry => {
        if (!entry.isIntersecting) return

        entry.target.classList.add("is-nudging")
        this.observer.unobserve(entry.target)
      })
    }, { threshold: 0.8 })
    this.itemTargets.forEach(item => this.observer.observe(item))
  }

  disconnect() {
    this.observer.disconnect()
  }
}
