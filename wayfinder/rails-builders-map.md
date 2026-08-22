# Find the Rails Builders Replacement

- Label: `wayfinder:map`
- Status: open

## Destination

Reach an implementation-ready product and technical specification for a production replacement of `rails.builders`, with every material v1 decision settled and ready to hand off through `to-spec` and `/kickstart-prototype-rails-app`.

## Notes

- Domain: [Rails Builders glossary](../CONTEXT.md)
- Initial data: [21 OG Builder seeds](assets/initial-og-builders.csv) — 20 email-only anonymous records plus Rich Steinmetz's public record.
- This is a focused enrollment, public-profile, and administration tool—not general community or live-session software.
- Public visual direction: funky, ruby-red, distinctly Rails-inspired, responsive, accessible, and meaningfully interactive.
- Public cards expose no personal or product information until explicit profile-level opt-in.
- Sessions resolving grilling tickets must use `grilling` and `domain-modeling`; prototype tickets must use `prototype`; research tickets must use `research`; public copy work should use `write-good-copy` and `no-ai-slop`.
- Planning is the default. Building and production cutover begin only after the map reaches its destination.

## Decisions so far

- [Research the ClickFunnels Newsletter Subscription API](tickets/research-clickfunnels-newsletter-api.md) — Reconcile verified, newsletter-confirmed contacts by email and the existing `newsletter-subscriber` tag; prove `General` topic delivery with a controlled smoke test.
- [Research Newsletter Consent Requirements](tickets/research-newsletter-consent.md) — Registration verification and privacy-policy disclosure are not newsletter consent; use a separate optional affirmative choice and newsletter-specific confirmation.
- [Research Slack Membership Automation](tickets/research-slack-membership-automation.md) — Dedicated-channel sync is feasible for existing workspace users, but workspace admission/removal is plan-dependent and may require an Administrator workflow.
- [Inventory the Rails Builders Slack Workspace](tickets/inventory-rails-builders-slack-workspace.md) — The private `#rails-builders` channel now exists; the settled Pro/Single-Channel-Guest design keeps admission and deactivation as an Owner/Admin workflow, with capacity and guest-agent behavior still to prove.
- [Define Seat Offers and Waitlist Promotion](tickets/define-seat-offers-and-waitlist-promotion.md) — Reserve capacity for 72-hour offers, launch with OG Priority, then automatically offer the Administrator-ordered waitlist; returning always requires explicit opt-in.

## Not yet specified

- Production runtime, uploaded-image storage, transactional email delivery, background-job operation, backups, and the `rails.builders` cutover path become specifiable after enrollment, profile-deletion, and integration behavior settle.
- Exact privacy-policy text, retention rules, and ClickFunnels failure recovery become specifiable after newsletter API and consent research.
- Acceptance seams and implementation slices become specifiable after the public-page prototype settles.

## Out of scope

- General-purpose community features such as messaging, feeds, payments, or arbitrary content management.
- Building Slack itself or generating meeting summaries and trend analysis in this app; these are external Rails Builders benefits. Only a possible Slack membership sync is under consideration.
- [Prototype the Shared-Pool Live Session Timer](tickets/prototype-shared-pool-session-timer.md) — Live-session controls, timers, attendance, and automated Three Strikes are excluded from v1 to keep the app focused.
- Shutting down the existing funnel, deploying production, or changing DNS during Wayfinder planning.
