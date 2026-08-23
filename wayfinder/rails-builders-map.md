# Ship Rails Builders

> Launch override (2026-08-22): follow the
> [direct production launch plan](direct-production-launch.md). Slack is handled
> manually outside the MVP promise, and the launch goes directly to the
> production hostname without an intermediate rehearsal app.

- Label: `wayfinder:map`
- Status: open

## Destination

Ship the current Rails Builders application to `rails.builders` on a single Hetzner server with settled membership rules, an Administrator-operated Slack Entitlement workflow, credential-backed ClickFunnels synchronization, tested SQLite backup and restore, and a rehearsed production cutover.

## Notes

- Domain: [Rails Builders glossary](../CONTEXT.md)
- Execution and acceptance plan: [Next Iteration Plan](next-iteration-plan.md)
- The current application, public copy, and visual design are the v1 baseline. Building is authorized; the map remains open until the production acceptance checks pass.
- Public cards expose no personal or Product information until the Builder opts in and a Facilitator approves publication.
- The current Free workspace cannot enforce Slack Entitlement. The settled ceiling is Pro, with Owner/Admin-operated Single-Channel Guest admission and deactivation tracked by the Rails application; the app must not claim automatic synchronization.

## Decisions so far

- [Research the ClickFunnels Newsletter Subscription API](tickets/research-clickfunnels-newsletter-api.md) — Upsert by verified, newsletter-confirmed email and idempotently reconcile the existing `newsletter-subscriber` tag.
- [Research Newsletter Consent Requirements](tickets/research-newsletter-consent.md) — Rails verification is not newsletter consent; retain the separate affirmative choice and newsletter confirmation.
- [Research Slack Membership Automation](tickets/research-slack-membership-automation.md) — Channel sync alone cannot enforce workspace Entitlement; supported workspace provisioning is unavailable at the settled plan ceiling.
- [Inventory the Rails Builders Slack Workspace](tickets/inventory-rails-builders-slack-workspace.md) — The private `#rails-builders` channel now exists; Pro Single-Channel Guests require manual Owner/Admin admission and deactivation, at least two paid active members are needed for nine guest Seats, and guest-agent behavior remains unproven.
- [Define Seat Offers and Waitlist Promotion](tickets/define-seat-offers-and-waitlist-promotion.md) — Reserve capacity for 72-hour offers, begin with OG Priority, and require explicit waitlist re-entry after leaving.
- [Define Administrator and Facilitator Authority](tickets/define-administrator-facilitator-and-session-authority.md) — Administrators control program and eligibility; Facilitators moderate publication; the last verified Administrator is protected.
- [Define the Active Builder and OG Builder Lifecycle](tickets/define-active-and-og-builder-lifecycle.md) — Enrollment controls are explicit, OG status is independent, and only Active Builders have Slack Entitlement.
- [Define Profile Publication and Account Deletion](tickets/define-profile-publication-and-account-deletion.md) — Publication is opt-in plus approval; account deletion removes local access immediately and durably queues manual Slack offboarding.
- [Define the Public Program Promise](tickets/define-public-program-promise.md) — Accept the current public copy as the baseline and keep operational ownership boundaries clear.
- [Choose Slack Membership Enforcement](tickets/choose-slack-membership-enforcement.md) — Derive Entitlement from Active Builder state and track the required Owner/Admin action to verified completion without claiming API synchronization.
- [Define the Verified Registration and Newsletter Flow](tickets/define-verified-registration-newsletter-flow.md) — Use encrypted Rails credentials in production, no-op locally, and sync only after both confirmations.
- [Prototype the Public Rails Builders Experience](tickets/prototype-public-rails-builders-experience.md) — The current implemented public experience is accepted; only regression QA remains.
- [Run the ClickFunnels Newsletter Delivery Smoke Test](tickets/run-clickfunnels-newsletter-smoke-test.md) — Test Only proved consent-gated upsert, single-tag reconciliation, `General` delivery, one-click unsubscribe, and blocked suppression; production keeps separate credentials.

## Remaining gates

- Before promising Slack access, upgrade to Pro, secure capacity for nine Single-Channel Guests, settle approved-domain self-join, and rehearse manual admission and offboarding with a disposable guest. Prove guest-agent interaction separately before promising it.
- Complete every automated, local end-to-end, backup/restore, cutover, and production smoke gate in the [Next Iteration Plan](next-iteration-plan.md).

## Next up: session experience

After this production iteration, plan and build:

- Session tracking and session history.
- Attendance tracking.
- The shared-pool session timer, using the earlier [timer prototype ticket](tickets/prototype-shared-pool-session-timer.md) only as historical input.
- Personalized session-summary creation, delivery, privacy, retention, and regeneration.

The next phase must first settle session lifecycle, facilitator authority during a session, attendance semantics, timer behavior, summary inputs, and who may see each summary.

## Out of scope

- General-purpose community features such as feeds, direct messaging, payments, or arbitrary content management.
- Horizontal application scaling while SQLite is the primary database. Revisit the database before adding a second application host.
- Slack Marketplace distribution or unsupported membership automation; v1 uses the documented Owner/Admin workflow for the Rails Builders workspace.
