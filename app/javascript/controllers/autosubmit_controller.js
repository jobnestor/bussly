import { Controller } from "@hotwired/stimulus"

// Submits the results filter form as soon as a sort or filter changes
export default class extends Controller {
  submit() { this.element.requestSubmit() }
}
