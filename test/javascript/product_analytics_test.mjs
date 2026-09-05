import assert from "node:assert/strict"
import test from "node:test"

const listeners = {}
const requests = []
const storedValues = new Map()

class MockElement {
  constructor(placement) {
    this.dataset = { analyticsPlacement: placement }
  }

  closest(selector) {
    return selector === "[data-analytics-placement]" ? this : null
  }
}

globalThis.Element = MockElement
globalThis.document = {
  body: {
    dataset: {
      posthogHost: "https://eu.i.posthog.com",
      posthogPath: "/sessions/:session",
      posthogRoute: "session",
      posthogToken: "phc_test_public_token"
    }
  },
  addEventListener: (event, callback) => { listeners[event] = callback }
}
globalThis.fetch = (url, options) => {
  requests.push({ url: url.toString(), options })
  return Promise.resolve()
}
globalThis.localStorage = {
  getItem: (key) => storedValues.get(key) || null,
  setItem: (key, value) => storedValues.set(key, value)
}
Object.defineProperty(globalThis, "navigator", {
  configurable: true,
  value: { doNotTrack: "0" }
})

await import(new URL("../../app/javascript/product_analytics.js", import.meta.url))

test("sends only the normalized anonymous analytics contract", () => {
  listeners["turbo:load"]()
  listeners.click({ target: new MockElement("hero") })
  listeners.click({ target: new MockElement("not-allowlisted") })

  assert.equal(requests.length, 2)
  assert.deepEqual(requests.map(({ url }) => url), [
    "https://eu.i.posthog.com/i/v0/e/",
    "https://eu.i.posthog.com/i/v0/e/"
  ])

  const events = requests.map(({ options }) => JSON.parse(options.body))
  assert.equal(events[0].event, "$pageview")
  assert.equal(events[0].properties.route, "session")
  assert.equal(events[1].event, "join_cta_clicked")
  assert.equal(events[1].properties.placement, "hero")
  assert.equal(events[0].distinct_id, events[1].distinct_id)

  for (const event of events) {
    assert.equal(event.api_key, "phc_test_public_token")
    assert.equal(event.properties.$pathname, "/sessions/:session")
    assert.equal(event.properties.$process_person_profile, false)
    assert.equal(event.properties.$geoip_disable, true)
    assert.deepEqual(Object.keys(event.properties).sort(), event.event === "$pageview"
      ? ["$geoip_disable", "$pathname", "$process_person_profile", "route"]
      : ["$geoip_disable", "$pathname", "$process_person_profile", "placement"])
  }

  assert.deepEqual(requests[0].options, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    credentials: "omit",
    referrerPolicy: "no-referrer",
    keepalive: true,
    body: requests[0].options.body
  })

  document.body.dataset = {}
  listeners["turbo:load"]()
  navigator.doNotTrack = "1"
  document.body.dataset = {
    posthogHost: "https://eu.i.posthog.com",
    posthogPath: "/",
    posthogRoute: "home",
    posthogToken: "phc_test_public_token"
  }
  listeners["turbo:load"]()
  assert.equal(requests.length, 2)
})
