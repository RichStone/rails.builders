import assert from "node:assert/strict"
import { readFile } from "node:fs/promises"
import test from "node:test"

for (const [name, method, timer] of [
  ["session_timer", "heartbeat", "heartbeatTimer"],
  ["session_refresh", "check", "refreshTimer"]
]) {
  const source = await readFile(new URL(`../../app/javascript/controllers/${name}_controller.js`, import.meta.url), "utf8")
  const { default: Poller } = await import(`data:text/javascript;base64,${Buffer.from(source.replace('import { Controller } from "@hotwired/stimulus"', 'class Controller {}')).toString("base64")}`)

  test(`${name} stops polling and reloads after CSRF rejection or an authentication redirect`, async (t) => {
    const cleared = []
    const requests = []
    let reloads = 0
    t.mock.method(globalThis, "clearInterval", (id) => cleared.push(id))
    globalThis.document = { querySelector: () => ({ content: "old-token" }) }
    globalThis.window = { location: { reload: () => reloads++ } }

    for (const response of [{ status: 422, ok: false }, { redirected: true, ok: true }]) {
      globalThis.fetch = async (...args) => { requests.push(args); return response }
      const controller = new Poller()
      controller.element = { isConnected: true }
      controller[timer] = 123
      controller.urlValue = controller.heartbeatUrlValue = "/sessions/1/heartbeat"

      await controller[method]()
    }

    assert.equal(reloads, 2)
    assert.equal(cleared.filter((id) => id === 123).length, 2)
    for (const [url, options] of requests) {
      assert.equal(url, "/sessions/1/heartbeat")
      assert.equal(options.method, "PATCH")
      assert.equal(options.headers["X-CSRF-Token"], "old-token")
      assert.equal(options.credentials, "same-origin")
    }
  })

  test(`${name} ignores failed requests and responses from detached pages`, async () => {
    globalThis.document = { querySelector: () => null }
    globalThis.window = {
      location: { reload: () => assert.fail("unexpected reload") },
      Turbo: { visit: () => assert.fail("unexpected navigation") }
    }
    const controller = new Poller()
    controller.element = { isConnected: true }

    for (const response of [null, { status: 503, ok: false }]) {
      globalThis.fetch = async () => response
      await controller[method]()
    }

    for (const response of [{ status: 422, ok: false }, { redirected: true, ok: true }]) {
      let respond
      controller.element.isConnected = true
      globalThis.fetch = () => new Promise((resolve) => { respond = resolve })
      const pending = controller[method]()
      controller.element.isConnected = false
      respond(response)
      await pending
    }
  })
}
