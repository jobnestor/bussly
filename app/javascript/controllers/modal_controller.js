import { Controller } from "@hotwired/stimulus"

// Opens the checkout sheet when the "modal" turbo-frame loads; closes on Esc, backdrop or [data-close]
export default class extends Controller {
  static targets = ["dialog"]

  connect() {
    this.element.addEventListener("click", this.closeClick)
  }

  disconnect() {
    this.element.removeEventListener("click", this.closeClick)
  }

  open() {
    this.dialogTarget.classList.add("open")
    const first = this.dialogTarget.querySelector("input:not([type=hidden]), button")
    if (first) first.focus()
  }

  close() {
    this.dialogTarget.classList.remove("open")
    const frame = document.getElementById("modal")
    if (frame) { frame.removeAttribute("src"); frame.innerHTML = "" }
  }

  closeClick = (event) => {
    if (event.target.closest("[data-close]")) { event.preventDefault(); this.close() }
  }

  backdrop(event) {
    if (event.target === this.dialogTarget) this.close()
  }

  escape(event) {
    if (event.key === "Escape" && this.dialogTarget.classList.contains("open")) this.close()
  }
}
