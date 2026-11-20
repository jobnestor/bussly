import { Controller } from "@hotwired/stimulus"

// Booking form: trip-type toggle, swap, cruise fields
export default class extends Controller {
  static targets = ["type", "seg", "from", "to", "toField", "swap", "waitField", "retField", "sightFields", "cruise", "cruiseFields", "stopsField"]

  setType(event) {
    const ty = event.currentTarget.dataset.type
    this.typeTarget.value = ty
    this.segTargets.forEach(b => b.setAttribute("aria-pressed", b.dataset.type === ty))
    this.waitFieldTarget.hidden = ty !== "round"
    this.retFieldTarget.hidden = ty !== "multi"
    this.sightFieldsTarget.hidden = ty !== "sight"
    this.toFieldTarget.hidden = ty === "sight"
    this.swapTarget.hidden = ty === "sight"
    if (this.hasStopsFieldTarget) this.stopsFieldTarget.hidden = ty === "sight"
  }

  swap() {
    const a = this.fromTarget.value
    this.fromTarget.value = this.toTarget.value
    this.toTarget.value = a
  }

  toggleCruise() {
    this.cruiseFieldsTarget.hidden = !this.cruiseTarget.checked
  }
}
