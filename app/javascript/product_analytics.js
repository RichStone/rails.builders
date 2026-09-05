const allowedPlacements = new Set(["header", "hero", "format", "readiness", "footer"])
const storageKey = "rails_builders_analytics_id"
let memoryId

const bodyConfig = () => document.body?.dataset || {}

const anonymousId = () => {
  if (memoryId) return memoryId

  try {
    memoryId = localStorage.getItem(storageKey)
    if (!memoryId) {
      memoryId = crypto.randomUUID()
      localStorage.setItem(storageKey, memoryId)
    }
  } catch {
    memoryId = crypto.randomUUID()
  }

  return memoryId
}

const capture = (event, properties) => {
  const { posthogToken, posthogHost, posthogPath } = bodyConfig()
  if (!posthogToken || !posthogHost || !posthogPath || navigator.doNotTrack === "1") return

  fetch(new URL("/i/v0/e/", posthogHost), {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    credentials: "omit",
    referrerPolicy: "no-referrer",
    keepalive: true,
    body: JSON.stringify({
      api_key: posthogToken,
      distinct_id: anonymousId(),
      event,
      properties: {
        ...properties,
        $geoip_disable: true,
        $pathname: posthogPath,
        $process_person_profile: false
      }
    })
  }).catch(() => {})
}

document.addEventListener("turbo:load", () => {
  const { posthogRoute } = bodyConfig()
  if (posthogRoute) capture("$pageview", { route: posthogRoute })
})

document.addEventListener("click", (event) => {
  const target = event.target instanceof Element && event.target.closest("[data-analytics-placement]")
  if (!target) return

  const placement = target.dataset.analyticsPlacement
  if (allowedPlacements.has(placement)) capture("join_cta_clicked", { placement })
})
