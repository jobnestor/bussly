import { Controller } from "@hotwired/stimulus"

// Live trip map. The server works out where the bus is (simulated from the schedule);
// this controller draws the map, follows the road between stops and refreshes every 20 s.
// The demo slider asks the server for any moment of the trip day.
const OSRM = "https://router.project-osrm.org/route/v1/driving/"

export default class extends Controller {
  static targets = ["map", "label", "detail", "clock", "live", "slider"]
  static values = { url: String, start: String, end: String, active: Boolean }

  async connect() {
    this.roads = {}
    this.at = null
    try {
      this.L = await import("leaflet")
    } catch (e) {
      this.mapTarget.classList.add("nomap")
      this.mapTarget.textContent = ""
      return
    }
    this.draw()
    this.refresh()
    if (this.activeValue) this.timer = setInterval(() => this.refresh(), 20000)
  }

  disconnect() {
    clearInterval(this.timer)
    clearTimeout(this.debounce)
    if (this.map) this.map.remove()
  }

  draw() {
    const L = this.L
    const el = this.mapTarget
    const stops = JSON.parse(el.dataset.stops)
    const depot = JSON.parse(el.dataset.depot)
    this.map = L.map(el, { scrollWheelZoom: false, attributionControl: true })
    L.tileLayer("https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png", {
      maxZoom: 18, attribution: "© OpenStreetMap"
    }).addTo(this.map)
    const pts = stops.map(s => s.at)
    stops.forEach((s, i) => {
      L.marker(s.at, { icon: this.pin(i === 0 ? "A" : "B", "stop"), title: s.name, keyboard: false }).addTo(this.map)
    })
    if (depot.name !== stops[0].name) {
      L.marker(depot.at, { icon: this.pin("", "depot"), title: depot.name, keyboard: false }).addTo(this.map)
      pts.push(depot.at)
    }
    this.bus = L.marker(JSON.parse(el.dataset.position), { icon: this.pin("", "bus"), zIndexOffset: 1000, keyboard: false }).addTo(this.map)
    if (pts.length > 1) this.map.fitBounds(L.latLngBounds(pts), { padding: [36, 36] })
    else this.map.setView(pts[0], 12)
    if (stops.length > 1) this.road(stops[0].at, stops[1].at).then(line => {
      L.polyline(line, { color: "#0e4a5c", weight: 4, opacity: .75 }).addTo(this.map)
    })
  }

  pin(text, kind) {
    return this.L.divIcon({ className: `pin pin-${kind}`, html: `<span>${text}</span>`, iconSize: kind === "bus" ? [34, 34] : [26, 26] })
  }

  // Road geometry from the public OSRM demo server; straight line if it is unavailable
  async road(a, b) {
    const key = `${a}|${b}`
    if (this.roads[key]) return this.roads[key]
    let line = [a, b]
    try {
      const res = await fetch(`${OSRM}${a[1]},${a[0]};${b[1]},${b[0]}?overview=full&geometries=geojson`)
      if (res.ok) {
        const data = await res.json()
        const coords = data.routes?.[0]?.geometry?.coordinates
        if (coords?.length) line = coords.map(([lng, lat]) => [lat, lng])
      }
    } catch (e) { /* keep straight line */ }
    this.roads[key] = line
    return line
  }

  // Point a share f of the way along a polyline
  along(line, f) {
    if (line.length < 2) return line[0]
    const seg = []
    let total = 0
    for (let i = 1; i < line.length; i++) {
      const d = Math.hypot(line[i][0] - line[i - 1][0], (line[i][1] - line[i - 1][1]) * Math.cos(line[i][0] * Math.PI / 180))
      seg.push(d); total += d
    }
    let target = total * f
    for (let i = 0; i < seg.length; i++) {
      if (target <= seg[i]) {
        const t = seg[i] ? target / seg[i] : 0
        return [line[i][0] + (line[i + 1][0] - line[i][0]) * t, line[i][1] + (line[i + 1][1] - line[i][1]) * t]
      }
      target -= seg[i]
    }
    return line[line.length - 1]
  }

  async refresh() {
    const url = new URL(this.urlValue, window.location.origin)
    if (this.at) url.searchParams.set("at", this.at)
    let s
    try {
      const res = await fetch(url, { headers: { Accept: "application/json" } })
      if (!res.ok) return
      s = await res.json()
    } catch (e) { return }
    this.labelTarget.textContent = s.label
    this.detailTarget.textContent = s.detail || ""
    this.clockTarget.textContent = s.clock
    this.liveTarget.hidden = !s.leg
    let pos = s.position
    if (s.leg) pos = this.along(await this.road(s.leg.from, s.leg.to), s.fraction)
    if (this.bus) this.bus.setLatLng(pos)
  }

  scrub() {
    const start = Date.parse(this.startValue), end = Date.parse(this.endValue)
    const t = new Date(start + (end - start) * (this.sliderTarget.value / 1000))
    this.at = t.toISOString()
    clearTimeout(this.debounce)
    this.debounce = setTimeout(() => this.refresh(), 120)
  }

  live() {
    this.at = null
    if (this.hasSliderTarget) this.sliderTarget.value = 0
    this.refresh()
  }
}
