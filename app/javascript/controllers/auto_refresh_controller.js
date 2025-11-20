import { Controller } from "@hotwired/stimulus"

// Connects to data-controller="auto-refresh"
export default class extends Controller {
  static values = {
    interval: { type: Number, default: 2000 }, // Default 2 seconds
    url: { type: String, default: "" }
  }

  connect() {
    this.startAutoRefresh()
  }

  disconnect() {
    this.stopAutoRefresh()
  }

  startAutoRefresh() {
    this.timer = setTimeout(() => {
      if (this.urlValue && this.urlValue !== "") {
        // If URL is specified, navigate to it
        window.location.href = this.urlValue
      } else {
        // Otherwise, reload the current page
        window.location.reload()
      }
    }, this.intervalValue)
  }

  stopAutoRefresh() {
    if (this.timer) {
      clearTimeout(this.timer)
    }
  }
}
