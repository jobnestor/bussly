import { Controller } from "@hotwired/stimulus"

// Copies the passenger tracking link
export default class extends Controller {
  static targets = ["source"]

  async copy(event) {
    const btn = event.currentTarget
    const text = this.sourceTarget.value
    try { await navigator.clipboard.writeText(text) } catch (e) { this.sourceTarget.select(); document.execCommand("copy") }
    const old = btn.textContent
    btn.textContent = btn.dataset.copyDoneValue || "✓"
    setTimeout(() => { btn.textContent = old }, 1800)
  }
}
