import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  explode(event) {
    if (event.button !== 0 || event.metaKey || event.ctrlKey || event.shiftKey || event.altKey || window.matchMedia("(prefers-reduced-motion: reduce)").matches) return

    event.preventDefault()
    if (this.element.classList.contains("is-exploding")) return

    this.element.classList.add("is-exploding")
    for (let index = 0; index < 16; index++) {
      const angle = index / 16 * Math.PI * 2
      const gem = document.createElement("span")
      gem.className = "ruby-burst-gem"
      gem.textContent = "◆"
      gem.style.setProperty("--burst-x", `${Math.cos(angle) * (55 + index % 3 * 18)}px`)
      gem.style.setProperty("--burst-y", `${Math.sin(angle) * (55 + index % 3 * 18)}px`)
      gem.style.setProperty("--burst-delay", `${index % 4 * 20}ms`)
      this.element.append(gem)
    }

    setTimeout(() => window.location.assign(this.element.href), 620)
  }
}
