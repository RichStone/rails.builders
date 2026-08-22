# Run the ClickFunnels Newsletter Delivery Smoke Test

- Label: `wayfinder:task`
- Order: 40
- Status: closed
- Assignee: Rich Steinmetz via Codex
- Parent: [Ship Rails Builders](../rails-builders-map.md)
- Blocked by: [Research the ClickFunnels Newsletter Subscription API](research-clickfunnels-newsletter-api.md)

## Question

Keep development and test as no-ops, reserve encrypted Rails credentials for the separate production profile, and verify the job upserts a contact only after Rails email verification and newsletter confirmation. Using the isolated `test-only` profile and a controlled consenting address, then prove tag reconciliation, `General` topic delivery, one-click unsubscribe, and suppression on a later retry.
