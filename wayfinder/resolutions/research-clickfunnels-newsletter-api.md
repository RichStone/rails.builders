# Resolution: ClickFunnels Newsletter Subscription API

Resolved by [the cited research](../research/clickfunnels-newsletter-api.md): after newsletter-specific confirmation, upsert the Loop Labs contact by verified email, reject/flag suppressed contacts, and idempotently reconcile the existing `newsletter-subscriber` tag (`448334` / `jYqAlB`). Do not overwrite `tag_ids`, create duplicate contacts/tags, or enroll the existing page-opt-in workflow by default. ClickFunnels publishes no contact-to-email-topic enrollment endpoint, so broadcasts must use the `General` topic plus a filter for the newsletter tag, and a controlled delivery/unsubscribe smoke test is required before production.

