// The rail drawer's checkbox is the single source of truth for the rail's
// width, but every live navigation rebuilds the DOM, so the checked state
// starts from localStorage and the change listener keeps it stored.
//
// First visit: default open on desktop (>= 1024px, the `lg` breakpoint the
// drawer's width classes are built around) and closed on small screens.
// Later visits: whatever the visitor last chose, on every screen size.
const STORAGE_KEY = "girihelix:rail-open"

export const RailDrawer = {
  mounted() {
    const checkbox = this.el.querySelector("#rail-drawer")

    const stored = localStorage.getItem(STORAGE_KEY)
    const open =
      stored === null ? matchMedia("(min-width: 1024px)").matches : stored === "true"

    checkbox.checked = open

    checkbox.addEventListener("change", () => {
      localStorage.setItem(STORAGE_KEY, checkbox.checked)
    })
  },
}