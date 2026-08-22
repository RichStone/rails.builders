# Resolution: Run the ClickFunnels Newsletter Delivery Smoke Test

The isolated `test-only` profile proved the exact consent-gated path without using production credentials. A Registrant separately confirmed the newsletter and Rails email; the Rails reconciler upserted one active contact, applied `newsletter-subscriber` once, and a forced retry left one contact and one tag.

A `General` broadcast filtered by that tag and the controlled address targeted and delivered to exactly one recipient. The standard one-click unsubscribe completed, ClickFunnels changed the contact to inactive with `unsubscribed_at`, and a later Rails retry recorded `blocked_suppressed` without reapplying the tag.

Development and test remain no-op by default. An explicit local smoke mode is bound to the `test-only` workspace and receives the token only through an inherited file descriptor. Production reads a separate target and token from encrypted `clickfunnels.*` Rails credentials; those production values must be supplied during deployment and are not copied from Test Only.
