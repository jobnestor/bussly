import { Controller } from "@hotwired/stimulus"

// Extra stops on the quote form. Suggestions come from /steder (preset places + Kartverket place names
// and addresses). The visible input shows the label; the hidden stops[] input carries the exact place.
export default class extends Controller {
  static targets = ["list", "tpl", "add", "suggest", "label"]
  static values = { url: String, max: Number }

  connect() {
    this.choices = new Map()
    this.toggle()
  }

  add() {
    if (this.rows().length >= this.maxValue) return
    this.listTarget.insertAdjacentHTML("beforeend", this.tplTarget.innerHTML)
    this.toggle()
    this.rows().at(-1).querySelector(".stop-in").focus()
  }

  remove(event) {
    event.currentTarget.closest(".stop").remove()
    this.toggle()
  }

  suggest(event) {
    const input = event.currentTarget
    this.pick(event)
    clearTimeout(this.timer)
    const q = input.value.trim()
    if (q.length < 2) return
    this.timer = setTimeout(async () => {
      try {
        const res = await fetch(`${this.urlValue}?q=${encodeURIComponent(q)}`, { headers: { Accept: "application/json" } })
        if (!res.ok) return
        const items = await res.json()
        this.suggestTarget.replaceChildren(...items.map(it => {
          this.choices.set(it.label, it.value)
          const o = document.createElement("option")
          o.value = it.label
          return o
        }))
      } catch (_) { /* offline: no suggestions */ }
    }, 200)
  }

  // Typed text that matches a suggestion (or a preset place) becomes the stop; anything else is checked server-side
  pick(event) {
    const input = event.currentTarget
    const hidden = input.parentElement.querySelector("input[type=hidden]")
    const v = input.value.trim()
    hidden.value = this.choices.get(v) || v
  }

  rows() { return Array.from(this.listTarget.querySelectorAll(".stop")) }

  toggle() {
    const n = this.rows().length
    this.addTarget.hidden = n >= this.maxValue
    this.labelTarget.hidden = n === 0
  }
}
