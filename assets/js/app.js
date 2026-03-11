// If you want to use Phoenix channels, run `mix help phx.gen.channel`
// to get started and then uncomment the line below.
// import "./user_socket.js"

// You can include dependencies in two ways.
//
// The simplest option is to put them in assets/vendor and
// import them using relative paths:
//
//     import "../vendor/some-package.js"
//
// Alternatively, you can `npm install some-package --prefix assets` and import
// them using a path starting with the package name:
//
//     import "some-package"
//
// If you have dependencies that try to import CSS, esbuild will generate a separate `app.css` file.
// To load it, simply add a second `<link>` to your `root.html.heex` file.

// Include phoenix_html to handle method=PUT/DELETE in forms and buttons.
import "phoenix_html"
// Establish Phoenix Socket and LiveView configuration.
import {Socket} from "phoenix"
import {LiveSocket} from "phoenix_live_view"
import {hooks as colocatedHooks} from "phoenix-colocated/synkade"
import topbar from "../vendor/topbar"

const DRAGGABLE_COLUMNS = ["backlog", "queue"]

const KanbanDrag = {
  mounted() {
    this.el.addEventListener("dragstart", (e) => {
      const card = e.target.closest(".kanban-card")
      if (!card) return
      const fromColumn = card.dataset.column
      if (!DRAGGABLE_COLUMNS.includes(fromColumn)) {
        e.preventDefault()
        return
      }
      e.dataTransfer.setData("issue_id", card.dataset.issueId)
      e.dataTransfer.setData("from_column", fromColumn)
      e.dataTransfer.effectAllowed = "move"
      card.classList.add("opacity-50")
    })

    this.el.addEventListener("dragend", (e) => {
      const card = e.target.closest(".kanban-card")
      if (card) card.classList.remove("opacity-50")
      this.el.querySelectorAll(".kanban-column").forEach((col) => {
        col.classList.remove("bg-base-300")
      })
    })

    this.el.addEventListener("dragover", (e) => {
      const column = e.target.closest(".kanban-column")
      if (!column) return
      if (column.dataset.droppable !== "true") return

      e.preventDefault()
      e.dataTransfer.dropEffect = "move"
      this.el.querySelectorAll(".kanban-column").forEach((col) => {
        col.classList.remove("bg-base-300")
      })
      column.classList.add("bg-base-300")
    })

    this.el.addEventListener("dragleave", (e) => {
      const column = e.target.closest(".kanban-column")
      if (column && !column.contains(e.relatedTarget)) {
        column.classList.remove("bg-base-300")
      }
    })

    this.el.addEventListener("drop", (e) => {
      e.preventDefault()
      const column = e.target.closest(".kanban-column")
      if (!column) return
      if (column.dataset.droppable !== "true") return

      column.classList.remove("bg-base-300")

      const issueId = e.dataTransfer.getData("issue_id")
      const fromColumn = e.dataTransfer.getData("from_column")
      const toColumn = column.dataset.column

      if (issueId && fromColumn && toColumn && fromColumn !== toColumn) {
        this.pushEvent("move_card", {
          issue_id: issueId,
          from_column: fromColumn,
          to_column: toColumn,
        })
      }
    })
  },
}

const AutoScroll = {
  mounted() {
    this.observer = new MutationObserver(() => {
      this.el.scrollTop = this.el.scrollHeight
    })
    this.observer.observe(this.el, { childList: true, subtree: true })
    this.el.scrollTop = this.el.scrollHeight
  },
  updated() {
    this.el.scrollTop = this.el.scrollHeight
  },
  destroyed() {
    if (this.observer) this.observer.disconnect()
  },
}

const csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content")
const liveSocket = new LiveSocket("/live", Socket, {
  longPollFallbackMs: 2500,
  params: {_csrf_token: csrfToken},
  hooks: {...colocatedHooks, KanbanDrag, AutoScroll},
})

// Clipboard copy handler for phx:copy events
window.addEventListener("phx:copy", (event) => {
  const text = event.detail.text
  if (text && navigator.clipboard) {
    navigator.clipboard.writeText(text)
  }
})

// Show progress bar on live navigation and form submits
topbar.config({barColors: {0: "#29d"}, shadowColor: "rgba(0, 0, 0, .3)"})
window.addEventListener("phx:page-loading-start", _info => topbar.show(300))
window.addEventListener("phx:page-loading-stop", _info => topbar.hide())

// connect if there are any LiveViews on the page
liveSocket.connect()

// expose liveSocket on window for web console debug logs and latency simulation:
// >> liveSocket.enableDebug()
// >> liveSocket.enableLatencySim(1000)  // enabled for duration of browser session
// >> liveSocket.disableLatencySim()
window.liveSocket = liveSocket

// The lines below enable quality of life phoenix_live_reload
// development features:
//
//     1. stream server logs to the browser console
//     2. click on elements to jump to their definitions in your code editor
//
if (process.env.NODE_ENV === "development") {
  window.addEventListener("phx:live_reload:attached", ({detail: reloader}) => {
    // Enable server log streaming to client.
    // Disable with reloader.disableServerLogs()
    reloader.enableServerLogs()

    // Open configured PLUG_EDITOR at file:line of the clicked element's HEEx component
    //
    //   * click with "c" key pressed to open at caller location
    //   * click with "d" key pressed to open at function component definition location
    let keyDown
    window.addEventListener("keydown", e => keyDown = e.key)
    window.addEventListener("keyup", _e => keyDown = null)
    window.addEventListener("click", e => {
      if(keyDown === "c"){
        e.preventDefault()
        e.stopImmediatePropagation()
        reloader.openEditorAtCaller(e.target)
      } else if(keyDown === "d"){
        e.preventDefault()
        e.stopImmediatePropagation()
        reloader.openEditorAtDef(e.target)
      }
    }, true)

    window.liveReloader = reloader
  })
}

