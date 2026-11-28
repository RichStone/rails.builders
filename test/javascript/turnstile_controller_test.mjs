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
  assert.equal(options.appearance, "interaction-only", "verification stays hidden unless Cloudflare requires interaction")
  assert.equal(options.size, "normal", "interactive verification uses the horizontal layout")
  options.callback("not-logged-or-stored")
  assert.equal(controller.submitTarget.disabled, false)
  assert.equal(controller.statusTarget.textContent, "Browser verified.")
})
