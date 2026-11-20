import { Controller } from "@hotwired/stimulus"

// Rate card editor: live preview + Bussly-minimum highlighting on every edit, busy-date chips
export default class extends Controller {
  static targets = ["status", "blockDate", "blocked", "rate"]
  static values = { previewUrl: String, floor: Number }

  input(event) {
    if (event.target === this.blockDateTarget) return
    if (event.target.name === "operator[depot]") this.depotChanged = true
    this.statusTarget.textContent = ""
    this.markLow()
    clearTimeout(this.timer)
    this.timer = setTimeout(() => this.preview(), 250)
  }

  markLow() {
    this.rateTargets.forEach(i => {
      const count = Number(this.element.querySelector(`[data-count-for="${i.dataset.cls}"]`)?.value || 0)
      const sug = Number(i.dataset.suggested)
      i.classList.toggle("low", count > 0 && Number(i.value) < sug * this.floorValue)
    })
  }

  async preview() {
    const body = new FormData(this.element)
    body.delete("_method")
    if (this.depotChanged) { body.set("depot_changed", "1"); this.depotChanged = false }
    const res = await fetch(this.previewUrlValue, {
      method: "POST", body,
      headers: { "Accept": "text/vnd.turbo-stream.html", "X-CSRF-Token": document.querySelector("meta[name=csrf-token]")?.content }
    })
    if (res.ok) { window.Turbo.renderStreamMessage(await res.text()); this.markLow() }
  }

  // Fill in suggested rates for the depot (not saved until the operator clicks Save)
  suggest(event) {
    event.preventDefault()
    this.rateTargets.forEach(i => { i.value = i.dataset.suggested })
    this.element.querySelectorAll('input[name$="[minH]"]').forEach(i => { i.value = 4 })
    const sur = { sur_weekend: 10, sur_peak: 12, sur_night: 15 }
    Object.entries(sur).forEach(([k, v]) => { const el = this.element.querySelector(`[name="operator[${k}]"]`); if (el) el.value = v })
    this.markLow()
    this.preview()
    this.statusTarget.className = "status"
    this.statusTarget.textContent = event.currentTarget.dataset.message
  }

  addBlocked() {
    const v = this.blockDateTarget.value
    if (!v || this.blockedTarget.querySelector(`input[value="${v}"]`)) return
    const chip = document.createElement("button")
    chip.type = "button"
    chip.dataset.action = "rate-card#removeBlocked"
    chip.textContent = `${v} ×`
    const hidden = document.createElement("input")
    hidden.type = "hidden"; hidden.name = "operator[blocked_dates][]"; hidden.value = v
    chip.appendChild(hidden)
    this.blockedTarget.appendChild(chip)
    this.preview()
  }

  removeBlocked(event) {
    event.currentTarget.remove()
    this.preview()
  }
}
