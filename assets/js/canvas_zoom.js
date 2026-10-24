// Pan and zoom for every workbench canvas.
//
// The transform lives on the inner [data-zoom-content] wrapper; the outer
// element (#canvas) clips, so panning reveals the SVG's fringe beyond the
// pinned viewport without moving the page layout. State is held on the hook,
// so a LiveView patch of the frame keeps the current view; unmounting and
// remounting starts again at scale 1, translation 0.
const MIN_SCALE = 0.6
const MAX_SCALE = 8.0

export const CanvasZoom = {
  mounted() {
    this.content = this.el.querySelector("[data-zoom-content]")
    this.scale = 1
    this.x = 0
    this.y = 0
    this.pointers = new Map()
    this.lastDistance = 0
    // Touch is ours: one finger pans, two pinch. Without this the browser
    // would scroll the page instead of reporting the gesture.
    this.el.style.touchAction = "none"
    this.el.addEventListener("pointerdown", e => this.down(e))
    this.el.addEventListener("pointermove", e => this.move(e))
    this.el.addEventListener("pointerup", e => this.up(e))
    this.el.addEventListener("pointercancel", e => this.up(e))
    // Non-passive so ctrl/meta-wheel can preventDefault. A plain wheel returns
    // before preventDefault, so the page still scrolls.
    this.el.addEventListener("wheel", e => this.wheel(e), {passive: false})
    for (const button of this.el.querySelectorAll("[data-zoom]")) {
      button.addEventListener("click", () => this.button(button.dataset.zoom))
    }
    this.apply()
  },
  destroyed() {
    this.el.style.touchAction = ""
  },
  down(e) {
    if (e.target.closest("[data-zoom]")) return
    this.el.setPointerCapture(e.pointerId)
    this.pointers.set(e.pointerId, {x: e.clientX, y: e.clientY})
  },
  move(e) {
    const previous = this.pointers.get(e.pointerId)
    if (!previous) return
    const next = {x: e.clientX, y: e.clientY}
    this.pointers.set(e.pointerId, next)
    if (this.pointers.size === 1) {
      this.x += next.x - previous.x
      this.y += next.y - previous.y
    } else {
      const [a, b] = [...this.pointers.values()]
      const distance = Math.hypot(a.x - b.x, a.y - b.y)
      if (this.lastDistance) {
        const rect = this.el.getBoundingClientRect()
        this.zoomAt((a.x + b.x) / 2, (a.y + b.y) / 2, rect, distance / this.lastDistance)
      }
      this.lastDistance = distance
    }
    this.apply()
  },
  up(e) {
    this.pointers.delete(e.pointerId)
    if (this.pointers.size < 2) this.lastDistance = 0
  },
  wheel(e) {
    if (!(e.ctrlKey || e.metaKey)) return
    e.preventDefault()
    const rect = this.el.getBoundingClientRect()
    this.zoomAt(e.clientX, e.clientY, rect, Math.exp(-e.deltaY * 0.002))
  },
  zoomAt(clientX, clientY, rect, factor) {
    const next = Math.min(MAX_SCALE, Math.max(MIN_SCALE, this.scale * factor))
    const applied = next / this.scale
    const px = clientX - rect.left - this.x
    const py = clientY - rect.top - this.y
    this.x -= px * (applied - 1)
    this.y -= py * (applied - 1)
    this.scale = next
  },
  button(action) {
    const rect = this.el.getBoundingClientRect()
    const centreX = rect.left + rect.width / 2
    const centreY = rect.top + rect.height / 2
    if (action === "in") this.zoomAt(centreX, centreY, rect, 1.25)
    if (action === "out") this.zoomAt(centreX, centreY, rect, 0.8)
    if (action === "reset") {
      this.scale = 1
      this.x = 0
      this.y = 0
    }
    this.apply()
  },
  apply() {
    if (!this.content) return
    this.content.style.transformOrigin = "0 0"
    this.content.style.transform = `translate(${this.x}px, ${this.y}px) scale(${this.scale})`
  }
}
