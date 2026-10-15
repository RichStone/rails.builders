import assert from "node:assert/strict"
import { readFile } from "node:fs/promises"
import test from "node:test"

const source = await readFile(new URL("../../app/javascript/controllers/session_timer_controller.js", import.meta.url), "utf8")
const { default: SessionTimerController } = await import(`data:text/javascript;base64,${Buffer.from(source.replace('import { Controller } from "@hotwired/stimulus"', 'class Controller {}')).toString("base64")}`)

test("countdown warnings escalate, clear on pause, and never appear for count-up timers", (t) => {
  t.mock.method(Date, "now", () => 100_000)
  const classes = new Set()
  const controller = new SessionTimerController()
  controller.element = { classList: { toggle: (name, enabled) => enabled ? classes.add(name) : classes.delete(name) } }
  controller.displayTarget = { textContent: "" }
  controller.warningTarget = { textContent: "" }
  controller.renderedAtValue = Date.now()
  controller.stateValue = "connection"

  for (const [seconds, mode, paused, className, warning] of [
    [31, "countdown", false, null, ""],
    [30, "countdown", false, "timer-amber", "⚠️ Wrap up soon"],
    [11, "countdown", false, "timer-amber", "⚠️ Wrap up soon"],
    [10, "countdown", false, "timer-red", "🚨 Final seconds"],
    [1, "countdown", false, "timer-red", "🚨 Final seconds"],
    [0, "countdown", false, "timer-red", "🚨 Time is up"],
    [-1, "countdown", false, "timer-red", "🚨 Time is up"],
    [10, "countdown", true, null, ""],
    [10, "countdown", false, "timer-red", "🚨 Final seconds"],
    [31, "countdown", false, null, ""],
    [0, "countup", false, null, ""],
    [30, "countup", false, null, ""]
  ]) {
    controller.secondsValue = seconds
    controller.modeValue = mode
    controller.pausedValue = paused
    controller.tick()
    assert.deepEqual([...classes], className ? [className] : [])
    assert.equal(controller.warningTarget.textContent, warning)
  }
})

test("a heartbeat from a detached page does not replace the current page", async () => {
  let respond
  const visits = []
  globalThis.document = { querySelector: () => null }
  globalThis.window = {
    location: { href: "https://example.test/sessions/1" },
    Turbo: { visit: (...arguments_) => visits.push(arguments_) }
  }
  globalThis.fetch = () => new Promise((resolve) => { respond = resolve })

  const controller = new SessionTimerController()
  controller.element = { isConnected: true }
  controller.heartbeatUrlValue = "/sessions/1/heartbeat"
  controller.versionValue = "2026-09-13T12:00:00.000000Z"
  controller.stateValue = "connection"
  controller.pausedValue = false

  const heartbeat = controller.heartbeat()
  controller.element.isConnected = false
  respond({
    ok: true,
    json: async () => ({ version: "2026-09-13T12:00:01.000000Z", state: "builder_updates", paused: false })
  })
  await heartbeat

  assert.deepEqual(visits, [])
})
