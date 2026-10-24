// Pan and zoom for every workbench canvas.
//
// The transform lives on the inner [data-zoom-content] wrapper; the outer
// element (#canvas) clips, so panning reveals the SVG's fringe beyond the
// pinned viewport without moving the page layout. State is held on the hook,
// so a LiveView patch of the frame keeps the current view; unmounting and
// remounting starts again at scale 1, translation 0.
const MIN_SCALE = 0.6
const MAX_SCALE = 8.0
// Wheel deltas arrive in pixels (deltaMode 0), lines (1) or pages (2) depending
// on the browser and device. Normalise lines and pages to pixels before zooming
// so ctrl/⌘-wheel is not dead in Firefox's line mode.
const LINE_HEIGHT = 16

export const CanvasZoom = {
  mounted() {
    this.content = this.el.querySelector("[data-zoom-content]")
    this.scale = 1
    this.x = 0
    this.y = 0
    this.pointers = new Map()
    this.lastDistance = 0
    this.lastMidpoint = null
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
    this.el.style.userSelect = ""
  },
  down(e) {
    if (e.target.closest("[data-zoom]")) return
    if (e.pointerType === "mouse" && e.button !== 0) return
    this.el.setPointerCapture(e.pointerId)
    // A pan over SVG text must not paint a selection highlight.
    this.el.style.userSelect = "none"
    this.pointers.set(e.pointerId, {x: e.clientX, y: e.clientY})
    // A second finger starts a fresh pinch: stale values from the previous
    // gesture would otherwise make it jump.
    if (this.pointers.size === 2) {
      this.lastDistance = 0
      this.lastMidpoint = null
    }
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
      const midpoint = {x: (a.x + b.x) / 2, y: (a.y + b.y) / 2}
      // Two-finger drag pans by how far the midpoint moved, then zooms about it.
      if (this.lastMidpoint) {
        this.x += midpoint.x - this.lastMidpoint.x
        this.y += midpoint.y - this.lastMidpoint.y
      }
      this.lastMidpoint = midpoint
      const distance = Math.hypot(a.x - b.x, a.y - b.y)
      if (this.lastDistance) {
        const rect = this.el.getBoundingClientRect()
        this.zoomAt(midpoint.x, midpoint.y, rect, distance / this.lastDistance)
      }
      this.lastDistance = distance
    }
    this.apply()
  },
  up(e) {
    this.pointers.delete(e.pointerId)
    if (this.pointers.size === 0) this.el.style.userSelect = ""
    if (this.pointers.size < 2) {
      this.lastDistance = 0
      this.lastMidpoint = null
    }
  },
  wheel(e) {
    if (!(e.ctrlKey || e.metaKey)) return
    e.preventDefault()
    const rect = this.el.getBoundingClientRect()
    let delta = e.deltaY
    if (e.deltaMode === 1) delta *= LINE_HEIGHT
    else if (e.deltaMode === 2) delta *= rect.height
    this.zoomAt(e.clientX, e.clientY, rect, Math.exp(-delta * 0.002))
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
      this.lastDistance = 0
      this.lastMidpoint = null
    }
    this.apply()
  },
  apply() {
    if (!this.content) return
    this.content.style.transformOrigin = "0 0"
    this.content.style.transform = `translate(${this.x}px, ${this.y}px) scale(${this.scale})`
  }
}
