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

// Restore persisted sidebar width before first paint to prevent layout flash.
;(function () {
  var w = localStorage.getItem("sidebar-width")
  if (w) document.documentElement.style.setProperty("--sidebar-w", w + "px")
})()

// Include phoenix_html to handle method=PUT/DELETE in forms and buttons.
import "phoenix_html"
// Establish Phoenix Socket and LiveView configuration.
import {Socket} from "phoenix"
import {LiveSocket} from "phoenix_live_view"
import {hooks as colocatedHooks} from "phoenix-colocated/synkade"
import topbar from "../vendor/topbar"


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

const CmdK = {
  mounted() {
    this._handler = (e) => {
      if ((e.metaKey || e.ctrlKey) && e.key === "k") {
        e.preventDefault()
        this.pushEvent("open_picker", {})
      }
    }
    window.addEventListener("keydown", this._handler)
  },
  destroyed() {
    window.removeEventListener("keydown", this._handler)
  },
}

const AutoFocus = {
  mounted() {
    this.el.focus()
  },
}

const ResizableSidebar = {
  mounted() {
    const handle = document.getElementById("sidebar-drag")
    if (!handle) return

    let dragging = false

    handle.addEventListener("mousedown", (e) => {
      e.preventDefault()
      dragging = true
      document.body.style.cursor = "col-resize"
      document.body.style.userSelect = "none"
    })

    document.addEventListener("mousemove", (e) => {
      if (!dragging) return
      const w = Math.max(180, Math.min(400, e.clientX))
      document.documentElement.style.setProperty("--sidebar-w", w + "px")
    })

    document.addEventListener("mouseup", () => {
      if (!dragging) return
      dragging = false
      document.body.style.cursor = ""
      document.body.style.userSelect = ""
      const w = getComputedStyle(document.documentElement).getPropertyValue("--sidebar-w").trim()
      localStorage.setItem("sidebar-width", parseInt(w, 10))
    })
  },
}

const ResizableSplit = {
  mounted() {
    const container = this.el
    const handle = container.querySelector("#ide-drag")
    if (!handle) return

    let dragging = false

    handle.addEventListener("mousedown", (e) => {
      e.preventDefault()
      dragging = true
      document.body.style.cursor = "col-resize"
      document.body.style.userSelect = "none"
    })

    document.addEventListener("mousemove", (e) => {
      if (!dragging) return
      const rect = container.getBoundingClientRect()
      const offset = e.clientX - rect.left
      const total = rect.width
      const handleWidth = 4
      const minLeft = 200
      const minRight = 150
      const rightWidth = Math.max(minRight, Math.min(total - minLeft - handleWidth, total - offset))
      const leftWidth = total - rightWidth - handleWidth

      if (leftWidth >= minLeft && rightWidth >= minRight) {
        container.style.setProperty("--split-right-w", rightWidth + "px")
      }
    })

    document.addEventListener("mouseup", () => {
      if (!dragging) return
      dragging = false
      document.body.style.cursor = ""
      document.body.style.userSelect = ""
    })
  },
}

const DiffComment = {
  mounted() {
    let dragStart = null
    let dragEnd = null
    let dragging = false

    const allLines = () => Array.from(this.el.querySelectorAll("[id^='diff-line-']"))

    const lineNumber = (el) => {
      const btn = el.querySelector(".diff-line-btn")
      return btn ? btn.dataset.line : null
    }

    const clearHighlight = () => {
      allLines().forEach((l) => l.classList.remove("!bg-primary/20"))
    }

    const highlightRange = (startEl, endEl) => {
      clearHighlight()
      const lines = allLines()
      const si = lines.indexOf(startEl)
      const ei = lines.indexOf(endEl)
      if (si < 0 || ei < 0) return
      const [from, to] = si <= ei ? [si, ei] : [ei, si]
      for (let i = from; i <= to; i++) {
        lines[i].classList.add("!bg-primary/20")
      }
    }

    this.el.addEventListener("mousedown", (e) => {
      const btn = e.target.closest(".diff-line-btn")
      if (!btn) return
      e.preventDefault()

      // Remove any existing comment input
      const existing = this.el.querySelector(".diff-comment-input")
      if (existing) existing.remove()
      clearHighlight()

      const lineDiv = btn.closest("[id^='diff-line-']")
      if (!lineDiv) return

      dragStart = lineDiv
      dragEnd = lineDiv
      dragging = true
      highlightRange(dragStart, dragEnd)
    })

    this.el.addEventListener("mousemove", (e) => {
      if (!dragging) return
      const lineDiv = e.target.closest("[id^='diff-line-']")
      if (!lineDiv || !lineNumber(lineDiv)) return
      dragEnd = lineDiv
      highlightRange(dragStart, dragEnd)
    })

    const finishDrag = () => {
      if (!dragging || !dragStart) return
      dragging = false

      const lines = allLines()
      const si = lines.indexOf(dragStart)
      const ei = lines.indexOf(dragEnd)
      const [from, to] = si <= ei ? [si, ei] : [ei, si]

      const startLine = lineNumber(lines[from])
      const endLine = lineNumber(lines[to])
      const file = lines[from].querySelector(".diff-line-btn")?.dataset.file
      const lastLineDiv = lines[to]
      if (!file || !startLine) { clearHighlight(); return }

      const lineLabel = startLine === endLine ? startLine : `${startLine}-${endLine}`

      // Create inline comment form
      const form = document.createElement("div")
      form.className = "diff-comment-input flex gap-2 px-3 py-2 bg-base-200 border-y border-base-300"
      form.innerHTML = `
        <input type="text" placeholder="Add comment for ${file}:${lineLabel}..."
          class="input input-xs input-bordered flex-1 font-mono text-xs" autofocus />
        <button class="btn btn-xs btn-primary">Send</button>
        <button class="btn btn-xs btn-ghost diff-comment-cancel">Cancel</button>
      `
      lastLineDiv.after(form)

      const input = form.querySelector("input")
      input.focus()

      const submit = () => {
        const text = input.value.trim()
        if (text) {
          this.pushEvent("comment_line", { file, line: lineLabel, text })
        }
        form.remove()
        clearHighlight()
      }

      form.querySelector(".btn-primary").addEventListener("click", submit)
      input.addEventListener("keydown", (ev) => {
        if (ev.key === "Enter") submit()
        if (ev.key === "Escape") { form.remove(); clearHighlight() }
      })
      form.querySelector(".diff-comment-cancel").addEventListener("click", () => { form.remove(); clearHighlight() })
    }

    this.el.addEventListener("mouseup", finishDrag)
  },
}

const SubmitOnEnter = {
  mounted() {
    this.el.addEventListener("keydown", (e) => {
      if (e.key === "Enter" && !e.shiftKey) {
        e.preventDefault()
        this.el.closest("form").dispatchEvent(new Event("submit", { bubbles: true, cancelable: true }))
      }
    })
    this.handleEvent("clear_input", () => {
      this.el.value = ""
    })
  },
}

const DropZone = {
  mounted() {
    const overlay = this.el.querySelector("[data-drop-overlay]")
    if (!overlay) return

    let dragCounter = 0

    this.el.addEventListener("dragenter", (e) => {
      e.preventDefault()
      dragCounter++
      overlay.classList.remove("hidden")
    })

    this.el.addEventListener("dragleave", (e) => {
      dragCounter--
      if (dragCounter <= 0) {
        dragCounter = 0
        overlay.classList.add("hidden")
      }
    })

    this.el.addEventListener("dragover", (e) => {
      e.preventDefault()
    })

    this.el.addEventListener("drop", () => {
      dragCounter = 0
      overlay.classList.add("hidden")
    })
  },
}

const CursorEnd = {
  mounted() {
    const el = this.el
    const len = el.value.length
    el.focus()
    el.setSelectionRange(len, len)
  },
}

const ToolTimer = {
  mounted() {
    this.startTime = Date.now()
    this.timerEl = this.el.querySelector("[data-timer]")
    if (!this.timerEl) return
    this.interval = setInterval(() => {
      const elapsed = (Date.now() - this.startTime) / 1000
      this.timerEl.textContent = elapsed < 10
        ? elapsed.toFixed(1) + "s"
        : Math.round(elapsed) + "s"
    }, 100)
  },
  destroyed() {
    if (this.interval) clearInterval(this.interval)
  },
}

const csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content")
const liveSocket = new LiveSocket("/live", Socket, {
  longPollFallbackMs: 2500,
  params: {_csrf_token: csrfToken},
  hooks: {...colocatedHooks, AutoScroll, DiffComment, ResizableSplit, ResizableSidebar, DropZone, SubmitOnEnter, CursorEnd, CmdK, AutoFocus, ToolTimer},
})

// Clipboard copy handler for phx:copy events
window.addEventListener("phx:copy", (event) => {
  const text = event.detail.text
  if (text && navigator.clipboard) {
    navigator.clipboard.writeText(text)
  }
})

// Theme switching via LiveView push_event
window.addEventListener("phx:set-theme", (event) => {
  document.documentElement.setAttribute("data-theme", event.detail.theme)
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

