import assert from "node:assert/strict"
import { readFile } from "node:fs/promises"
import test from "node:test"

const source = await readFile(new URL("../../app/javascript/controllers/turnstile_controller.js", import.meta.url), "utf8")
const { default: TurnstileController } = await import(`data:text/javascript;base64,${Buffer.from(source.replace('import { Controller } from "@hotwired/stimulus"', 'class Controller {}')).toString("base64")}`)

function form() {
  const controller = new TurnstileController()
  controller.element = { isConnected: true }
  controller.widgetTarget = {}
  controller.statusTarget = { textContent: "" }
  controller.retryTarget = { hidden: true }
  controller.submitTarget = { disabled: true }
  controller.siteKeyValue = "public-site-key"
  return controller
}

test("keeps sign in disabled until the browser challenge succeeds", async () => {
  let options
  globalThis.window = { turnstile: {
    ready: (callback) => callback(),
    render: (_element, configuration) => { options = configuration; return "widget-1" }
  } }
  const controller = form()
  await controller.connect()
  assert.equal(controller.submitTarget.disabled, true)
  assert.equal(options.sitekey, "public-site-key")
  assert.equal(options.action, "sign_in")
  assert.equal(options.size, "compact", "verification must fit the narrow sign-in card on mobile")
  options.callback("not-logged-or-stored")
  assert.equal(controller.submitTarget.disabled, false)
  assert.equal(controller.statusTarget.textContent, "Browser verified.")
})

test("errors offer an accessible retry and expired tokens are refreshed before resubmission", async () => {
  let options
  const resets = []
  window.turnstile = {
    ready: (callback) => callback(),
    render: (_element, configuration) => { options = configuration; return "widget-1" },
    reset: (widget) => resets.push(widget)
  }
  const controller = form()
  await controller.connect()
  options.callback("token")
  options["error-callback"]()
  assert.equal(controller.submitTarget.disabled, true)
  assert.equal(controller.retryTarget.hidden, false)
  assert.match(controller.statusTarget.textContent, /retry/i)
  controller.retry()
  assert.deepEqual(resets, ["widget-1"])
  assert.equal(controller.retryTarget.hidden, true)
  options.callback("fresh-token")
  options["expired-callback"]()
  assert.equal(controller.submitTarget.disabled, true)
  assert.deepEqual(resets, ["widget-1", "widget-1"])
  options["timeout-callback"]()
  assert.equal(controller.retryTarget.hidden, false)
})

test("Turbo snapshots and disconnects remove stale widgets and returning forms get a new token", async () => {
  let renders = 0
  let options
  const removed = []
  const resets = []
  window.turnstile = {
    ready: (callback) => callback(),
    render: (_element, configuration) => { options = configuration; return `widget-${++renders}` },
    remove: (widget) => removed.push(widget),
    reset: (widget) => resets.push(widget)
  }
  const controller = form()
  await controller.connect()
  options.callback("old-token")
  controller.beforeCache()
  assert.equal(controller.submitTarget.disabled, true)
  assert.deepEqual(removed, ["widget-1"])
  controller.disconnect()
  assert.deepEqual(removed, ["widget-1"])
  await controller.connect()
  assert.equal(renders, 2)
  controller.submitted({ detail: { success: false } })
  assert.deepEqual(resets, ["widget-2"])
})

test("a blocked script offers retry and navigation during loading never renders a stale widget", async () => {
  const scripts = []
  globalThis.document = {
    createElement: () => ({ remove() { this.removed = true } }),
    head: { append: (script) => scripts.push(script) },
    querySelector: () => ({ content: "page-script-nonce" })
  }
  window.turnstile = undefined
  const controller = form()
  const loading = controller.connect()
  assert.equal(scripts.length, 1)
  assert.equal(scripts[0].src, "https://challenges.cloudflare.com/turnstile/v0/api.js?render=explicit")
  scripts[0].onerror()
  await loading
  assert.equal(controller.retryTarget.hidden, false)
  assert.equal(controller.submitTarget.disabled, true)
  assert.equal(scripts[0].removed, true)

  const retrying = controller.retry()
  assert.equal(scripts.length, 2)
  controller.disconnect()
  let renders = 0
  window.turnstile = { ready: (callback) => callback(), render: () => renders++ }
  scripts[1].onload()
  await retrying
  assert.equal(renders, 0)
  await controller.connect()
  assert.equal(renders, 1)
})
