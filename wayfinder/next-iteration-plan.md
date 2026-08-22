# Rails Builders Next Iteration Plan

- Status: ready for implementation; Slack access remains gated by the Pro capacity and disposable-guest rehearsal
- Baseline: the current `main` branch and accepted public experience
- Outcome: production on `rails.builders`, with automated enrollment and ClickFunnels sync, an Administrator-operated Slack Entitlement workflow, and a tested recovery path

## Locked behavior

### Member controls

- The dashboard presents an **Active membership** switch for verified people. It is on only while the Builder is active. Turning it off is a voluntary withdrawal: release the Seat, offer it to the next eligible person, and queue Slack offboarding. When it is off, it is read-only with an explanation because a person cannot bypass capacity by switching it directly on; they return through the waitlist and Seat Offer flow.
- The dashboard presents a **Join the waitlist** switch whenever the person is eligible to choose. Turning it off clears queue position and records `left_waitlist`; turning it on joins the end of the queue and may immediately produce a Seat Offer when promotion is open and capacity is free.
- A pending Seat Offer keeps explicit Accept and Decline actions. It is not represented as a switch.
- Administrator removal records `removed`, releases any capacity, removes Slack Entitlement, and disables self-service re-entry until an Administrator reinstates the person.
- Turning off public-profile publication does not change enrollment or Slack. “Delete profile” in the roadmap means deleting the account.

### Roles and authority

- Members manage only their own enrollment choices, profile, Products, publication request, and account.
- Facilitators review publication requests and appear publicly. The role does not imply Administrator access and does not consume a Seat.
- Administrators manage program settings, queue order, eligibility and enrollment exceptions, roles, accounts, and integration retries.
- The last verified Administrator cannot be demoted or deleted through either the Administrator UI or self-service account deletion.
- Replace unrestricted Administrator status assignment with named lifecycle actions so capacity release, notification, and the Slack Administrator queue cannot be bypassed.

### Integrations

- Slack desired state is derived from enrollment: `active` means present as a Single-Channel Guest assigned only to `#rails-builders`; every other state means deactivated. Owner/Admin actions enforce that state, and Rails records requested and verified completion separately.
- ClickFunnels remains newsletter-specific. A Rails verification without newsletter confirmation is not sent to ClickFunnels.
- Production secrets live in encrypted Rails credentials. Development and test adapters make no external network calls.

## Implementation sequence

### 1. Enrollment controls and Administrator safety

- Add terminal enrollment states for `left_waitlist` and `removed`; include them in dashboard, mailer, and Administrator presentation.
- Add a waitlist opt-out transition that clears `waitlist_joined_at`, rank, and offer data without deleting the account.
- Route voluntary withdrawal, waitlist opt-in/out, Administrator removal/reinstatement, and deletion through model-level transition methods guarded by locks.
- Make repeated submissions idempotent and ensure every capacity-releasing transition promotes at most once.
- Replace the raw Administrator enrollment dropdown with explicit actions and confirmations.
- Enforce the last-Administrator invariant at the model boundary, not only in the controller.

### 2. Slack Administrator workflow and Pro rehearsal

- Treat the completed [Slack workspace inventory](tickets/inventory-rails-builders-slack-workspace.md) as authoritative: the workspace is Free today, the ceiling is Pro, and Single-Channel Guest provisioning and deactivation require manual Owner/Admin action.
- Before Slack access becomes a launch promise, upgrade to Pro, secure capacity for all nine guest Seats (at least two paid active members under the current allowance, or a documented alternative), and disable approved-domain self-join or explicitly accept that it breaks Entitlement enforcement.
- Do not add a Slack membership adapter, token, reconciliation job, or channel-only substitute. Pro exposes no supported API for the required guest lifecycle, and the Rails UI must not claim synchronization.
- Introduce a durable Slack access task, separate from the User lifecycle, containing the latest desired state, verified email, stable Slack team/user IDs once known, request time, observed completion time, status, and a bounded operational note. An offboarding task may temporarily survive account deletion solely to verify deactivation.
- Create or supersede the appropriate admission/offboarding task in the same local transaction as enrollment. Repeated transitions are idempotent, and the Administrator must see when a newer enrollment decision makes an older task stale.
- Provide an Administrator queue with explicit **Confirm admitted** and **Confirm deactivated** actions, pending and overdue states, and enough context to perform the Owner/Admin runbook. Remove the manually editable Slack status.
- After verified deleted-account cleanup, erase personal fields or reduce the task to a non-personal operational audit entry.
- Rehearse invitation, sole-channel visibility, deactivation, and reactivation with the disposable guest from the inventory. Test Hermes or Agentforce separately; neither is a membership mechanism or a public promise until guest interaction is proven.

### 3. ClickFunnels credential and production sync

- Read the token from `Rails.application.credentials.dig(:clickfunnels, :api_token)` rather than `CLICKFUNNELS_API_TOKEN`.
- In development and test, return a visible no-op result without making a request. In production, missing credentials are an Administrator-visible configuration failure.
- Preserve the current two-confirmation gate, normalized-email upsert, suppression check, idempotent tag reconciliation, timeouts, and retries.
- Follow the official contract: Bearer authentication and a required distinct User-Agent; upsert matches by email and can return 200 or 201. See [Authentication](https://developers.myclickfunnels.com/docs/authentication), [Upsert a Contact](https://developers.myclickfunnels.com/reference/upsertcontacts), and [Create Applied Tag](https://developers.myclickfunnels.com/reference/createcontactsappliedtags).
- Honor `Retry-After` for 429 responses, retry timeouts and 5xx responses, and expose permanent 4xx failures without retry loops.

### 4. Freeze the public experience

- Make no planned copy or visual redesign.
- Update only text required by shipped behavior. Keep Slack described as Administrator-managed and do not imply automatic provisioning.
- Treat the current desktop and mobile appearance, profile-review workflow, anonymity, and privacy behavior as regression contracts.

### 5. Hetzner production runtime

- Use one EU Hetzner Cloud server with a public Primary IP, deletion protection, a Cloud Firewall, and automatic daily Cloud Backups. Permit HTTP/HTTPS publicly and restrict SSH to the Administrator's source addresses.
- Deploy the existing Docker image with Kamal to one host. Kamal supplies health-gated replacement through `/up` and automatic TLS through `kamal-proxy`; see [Kamal installation](https://kamal-deploy.org/docs/installation/) and [proxy SSL](https://kamal-deploy.org/docs/configuration/proxy/).
- Bind `/srv/rails-builders/storage` on the host to `/rails/storage` in the container. Put the primary, cache, queue, and cable SQLite databases plus Active Storage uploads under that persistent path.
- Run one Puma application process with normal thread concurrency and Solid Queue supervised in the same container. Do not add a second application host while using SQLite.
- Keep `RAILS_MASTER_KEY` outside Git in Kamal secrets. Store the ClickFunnels token in encrypted Rails credentials; keep registry, host, Resend, Honeybadger, and application-host secrets in the deployment secret set. V1 has no Slack membership token.
- Use backward-compatible migrations because the old and new containers can overlap briefly during a health-gated deploy.

### 6. SQLite and uploaded-file backups

- Keep authoritative data on the server's root disk under `/srv/rails-builders/storage`, not an attached Cloud Volume: Hetzner Cloud Backups do not include attached Volumes and do not guarantee a consistent live filesystem image. See [Hetzner's backup FAQ](https://docs.hetzner.com/cloud/servers/backups-snapshots/faq/).
- Use encrypted Restic backups to a private Hetzner Object Storage bucket in a different EU location. Hetzner documents Restic's S3 backend, encryption, checks, and scheduled retention in its [Restic guide](https://docs.hetzner.com/storage/object-storage/howto-backups/restic/).
- Nightly, enter maintenance, stop the single app container so SQLite databases and uploads are one consistent snapshot, back up the persistent directory, restart, verify `/up`, then leave maintenance. Target less than two minutes of off-hours interruption.
- Retain 7 daily, 5 weekly, and 12 monthly Restic snapshots. Run `restic check` weekly and alert through Honeybadger or an Administrator email when backup, prune, restart, or health verification fails.
- Keep Hetzner's seven automatic daily server backups as a second recovery layer. They are not a substitute for application backups and disappear with the deleted server.
- Initial targets: recovery point objective of 24 hours and recovery time objective of 2 hours. Add continuous SQLite replication only if those targets become insufficient.
- Before launch and quarterly thereafter, restore Restic data onto a fresh disposable server, boot the app, verify record counts and an uploaded avatar, run migrations, process a queued job, and document elapsed recovery time.

## Missing automated tests to add

### Enrollment and authority

- Waitlisted Builder opts out: rank and timestamps clear, no offer is issued, repeated off is harmless.
- Eligible inactive Builder opts in: joins at the end; open capacity may immediately issue an offer; paused promotion and OG Priority remain respected.
- Active Builder turns membership off: exactly one Seat is released, exactly one current Slack offboarding task remains, and the next Builder is promoted once.
- Administrator removes an active, offered, waitlisted, and already-removed Builder; removed people cannot self-rejoin.
- Administrator reinstates eligibility without silently granting a Seat.
- The final verified Administrator cannot demote or delete themselves or be demoted/deleted by another action; a second Administrator makes those actions legal.
- Public-profile opt-out leaves enrollment and the current Slack task unchanged.
- Concurrent/repeated transition requests preserve the capacity invariant and the newest desired integration state.

### Slack

- Every transition into `active` creates or preserves one current admission task; every transition out creates or preserves one current offboarding task.
- Repeated or reversed transitions visibly supersede stale tasks so an Administrator cannot apply an older desired state by mistake.
- Account deletion retains only enough task data to verify deactivation; re-registration before cleanup makes the conflict explicit before either task can be completed.
- Confirming admission or deactivation requires Administrator authority, records the observer and time, and is idempotent.
- Stable Slack team/user IDs, once manually recorded, remain bound across later email changes unless an Administrator explicitly corrects the binding.
- Pending, overdue, blocked by plan/capacity, admitted, and deactivated states remain distinct and never appear as API-synchronized.
- No development, test, or production code attempts a Slack membership or channel-membership network request.

### ClickFunnels

- Development and test remain no-op even if a credential exists; production missing credential records configuration failure.
- Rails verification alone does not sync; newsletter confirmation alone does not sync; completion in either order syncs once.
- Credentials provide the Bearer token without leaking into logs or errors.
- Upsert accepts 200 and 201, handles malformed JSON, preserves suppression, avoids a duplicate tag, and splits optional names safely.
- 429 honors `Retry-After`; timeout/5xx retry; 400/401/404 are permanent and Administrator-visible.
- Repeated jobs and Administrator retries remain idempotent.

### Deployment and recovery

- Production configuration resolves every SQLite database and Active Storage root beneath `/rails/storage`.
- The production image boots with only documented secrets, runs `db:prepare`, returns 200 from `/up`, and starts Solid Queue.
- A container replacement preserves users, jobs, and an uploaded avatar.
- The backup script fails closed, restarts the app on error, reports failure, applies retention, and never records success before `restic check` and `/up` pass.
- An automated restore smoke script can restore the latest snapshot into a temporary directory and pass database integrity checks.

## Local end-to-end QA gate

Use a clean local database and real browser. ClickFunnels stays in no-op mode; Slack is exercised through the Administrator queue with no external network client.

1. Run `bin/setup`, `bin/rails db:seed`, and the full `bin/ci` pipeline.
2. Register a new non-OG without newsletter consent, verify the single-use link, confirm waitlist position, turn the waitlist off, and turn it on again at the end of the queue.
3. As Administrator, pause/open promotion, issue an offer, and verify Accept and Decline still behave correctly.
4. Accept a Seat, verify one pending Slack admission task appears, turn Active membership off, verify the Seat promotes once, and verify a current offboarding task supersedes admission.
5. Remove a Builder as Administrator and confirm self-service re-entry is unavailable; reinstate them and confirm only waitlist opt-in returns.
6. Attempt to demote and delete the last Administrator, then add a second Administrator and repeat the allowed path.
7. Request profile publication, approve as Facilitator, edit the Product to clear approval, turn publication off, and confirm none of those actions change enrollment or Slack.
8. Delete an active account and verify immediate sign-out, public removal, Seat promotion, and a durable pending Slack offboarding task containing only the allowed cleanup data.
9. Opt into the newsletter, complete its confirmation and Rails verification in both orders, and verify development records a no-op without an external request.
10. Check the accepted public page at narrow mobile, tablet, and desktop widths: navigation, countdown, anonymous cards, approved profiles, keyboard focus, labels, confirmations, and no horizontal overflow.
11. Build and run the production Docker image locally with a mounted temporary storage directory; restart/redeploy it and confirm the database and uploaded avatar survive.
12. Run the backup against that mounted directory, delete the disposable container/data, restore into a fresh directory, boot, and re-run the core sign-in/dashboard/avatar checks.

No production deploy starts until this checklist and all automated tests pass with recorded evidence.

## Production rehearsal and cutover

### Rehearsal

- Provision and harden the Hetzner server, configure Kamal, mount persistent storage, enable Cloud Backups, initialize Restic, and set deletion protection.
- Deploy to a temporary hostname, load production-like seed data without real personal addresses, verify TLS and `/up`, run email delivery to an operator, and complete a backup/restore drill.
- Confirm Resend domain, Honeybadger event delivery, recurring offer expiry/cleanup, Solid Queue, disk-space alerting, and server reboot recovery.
- If Slack access will launch, upgrade to Pro with enough guest capacity and use the authorized disposable account to prove manual invitation as a Single-Channel Guest, sole-channel visibility, deactivation, and reactivation. Settle approved-domain self-join before treating Entitlement as enforceable.

### Cutover

1. Lower the existing `rails.builders` DNS TTL at least 24 hours ahead.
2. Record the old site's rollback target and export any data that must survive.
3. Deploy the exact locally accepted commit, run migrations and idempotent seeds, and take a named pre-cutover Restic snapshot.
4. Point DNS to Hetzner, confirm automatic TLS, health, home page, privacy page, sign-in delivery, verification, dashboard, profile upload, and Administrator access.
5. With a controlled consenting address, complete the ClickFunnels upsert/tag/delivery/unsubscribe smoke test.
6. With the authorized disposable Slack account, accept a Seat, complete and record manual Single-Channel Guest admission, release the Seat, complete and record manual deactivation, and verify the Rails task history matches the observed workspace state.
7. Watch application, job, integration, backup, disk, and error state closely for 24 hours before raising DNS TTL.

### Rollback

- For an application defect, use Kamal rollback to the prior image when the schema remains compatible.
- For a cutover defect, restore the previous DNS target while preserving new Rails Builders data for reconciliation.
- Restore SQLite/uploads only for data loss or an incompatible migration, using the tested Restic runbook and integrity checks. Never overwrite newer production data merely to roll back code.
