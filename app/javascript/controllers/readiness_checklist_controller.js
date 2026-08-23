import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["checkbox", "unlock", "activation", "choice", "submit", "effects"]
  static values = { gated: { type: Boolean, default: true } }

  connect() {
    this.complete = false
    this.sync()
  }

  toggle(event) {
    const row = event.currentTarget.closest("[data-readiness-checklist-row]")
    if (event.currentTarget.checked) this.playCheckEffect(row)
    this.sync()
  }

  toggleChoice() {
    this.syncSubmit()
  }

  sync() {
    const complete = this.checkboxTargets.length > 0 && this.checkboxTargets.every((checkbox) => checkbox.checked)
    const wasComplete = this.complete
    this.complete = complete

    this.unlockTargets.forEach((target) => { target.hidden = !complete })
    this.activationTargets.forEach((target) => {
      target.hidden = this.gatedValue && !complete
      if (this.gatedValue && !complete) this.choiceTarget.checked = false
    })
    this.syncSubmit()

    if (complete && !wasComplete) this.celebrate()
  }

  syncSubmit() {
    if (!this.hasSubmitTarget) return

    this.submitTarget.disabled = this.gatedValue && (!this.complete || !this.choiceTarget.checked)
  }

  playCheckEffect(row) {
    if (!row || this.reducedMotion) return

    const effects = ["pop-wiggle", "pop-flip", "pop-jump", "pop-squish", "pop-slide"]
    row.classList.remove(...effects)
    requestAnimationFrame(() => row.classList.add(effects[Math.floor(Math.random() * effects.length)]))

    const pop = document.createElement("span")
    pop.className = "readiness-pop"
    pop.textContent = ["◆", "🚂", "✨", "🤝", "💥"][Math.floor(Math.random() * 5)]
    row.append(pop)
    pop.addEventListener("animationend", () => pop.remove(), { once: true })
  }

  celebrate() {
    if (!this.hasEffectsTarget || this.reducedMotion) return

    for (let index = 0; index < 64; index++) {
      const piece = document.createElement("i")
      const angle = Math.PI * 2 * index / 64
      const distance = 95 + Math.random() * 260
      piece.className = `readiness-confetti confetti-${index % 5}`
      piece.textContent = ["◆", "●", "▲", "■", "✦"][index % 5]
      piece.style.setProperty("--confetti-x", `${Math.cos(angle) * distance}px`)
      piece.style.setProperty("--confetti-y", `${Math.sin(angle) * distance}px`)
      piece.style.setProperty("--confetti-spin", `${360 + Math.random() * 720}deg`)
      piece.style.setProperty("--confetti-delay", `${Math.random() * 180}ms`)
      this.effectsTarget.append(piece)
      piece.addEventListener("animationend", () => piece.remove(), { once: true })
    }
  }

  get reducedMotion() {
    return window.matchMedia("(prefers-reduced-motion: reduce)").matches
  }
}
