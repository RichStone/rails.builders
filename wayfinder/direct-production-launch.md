# Rails Builders Direct Production Launch

- Updated: 2026-08-22
- Target: `rails.builders`
- Strategy: one SQLite writer on one Hetzner host, deployed directly with Kamal

## Settled launch scope

- Slack admission and removal stay fully manual. The Rails application may show
  an informational manual status, but v1 does not promise or implement a durable
  Slack task queue or any Slack API synchronization. Slack is therefore removed
  from the public MVP promise.
- Skip the rehearsal hostname for this launch. Build and boot the production
  image locally, deploy health-gated to the production host, and only then cut
  over the public DNS.
- Keep production SQLite databases and Active Storage together under
  `/srv/rails-builders/storage` on the server root disk. Run only one app host.
- Use Kamal/Thruster with TLS, `/up` health checks, and Solid Queue supervised by
  Puma.
- Keep secrets out of Git and ordinary worktrees. Track `.env.example`; ignore
  the operator's `.env`.

## Hosting and recovery decision

Use the lowest-cost available 4 GB Hetzner shared instance in the EU. A CX23
x86 host is preferred. Cost-optimized German capacity is unavailable at the
time of launch, so the purchase choice is either the same low-cost x86 shape in
Helsinki or the more expensive current German tier. Price is the priority unless
the operator chooses German residency at checkout.

Enable Hetzner's seven daily full-server backups and deletion protection. The
primary portable backup is a nightly application-quiesced Restic snapshot of
the whole persistent tree to an EU Backblaze B2 bucket, with 7 daily, 5 weekly,
and 12 monthly snapshots. Run a regular repository check and exercise a restore;
provider snapshots alone are not a SQLite consistency guarantee. See
[the cited hosting decision](research/sqlite-production-hosting.md).

## Launch sequence

1. Make CI green and run the full local pipeline.
2. Boot the production image locally with a disposable persistent mount and
   verify `/up`, database preparation, Solid Queue, and a restart against the
   same storage.
3. Finish Google OAuth, Resend domain authentication, Honeybadger, ClickFunnels
   credentials, and `hello@rails.builders` forwarding. Missing optional keys may
   be added after the first boot, but transactional email must work before public
   registration opens.
4. Provision the Hetzner server with SSH keys, a firewall, daily backups, and
   deletion protection. Configure the off-host Restic repository and install the
   backup units, but do not run them before an application container exists.
5. Build and push the accepted image to Docker Hub, set `KAMAL_PROXY_SSL=false`, run
   `kamal setup`, and smoke-test the host through an explicit `Host` header
   before DNS changes.
6. Run one coherent backup against the live container, pass the restore smoke
   check, and then enable the backup, repository-check, restore, and disk-capacity
   timers. Recovery is not ready until those checks pass.
7. Replace only the apex and `www` web records in Porkbun. Preserve the existing
   ClickFunnels email-authentication records and add the Resend records exactly
   as issued. Once both web records resolve to the host, set
   `KAMAL_PROXY_SSL=true` and deploy again to obtain TLS certificates.
8. Verify TLS, home/privacy pages, sign-in delivery, account verification,
   Administrator access, uploads, Google connection, Honeybadger reporting,
   ClickFunnels newsletter sync, jobs, restart recovery, backup age, and disk
   usage. Keep the old web targets recorded for DNS rollback.

## Remaining human gates

- Confirm the external account mutations when the prepared forms are ready.
- Complete the Hetzner paid-server purchase at checkout.
- Choose or create the Backblaze B2 EU account and execute the relevant DPA if
  that account is not already available.
- Manually copy/reveal third-party credentials into the approved local secret
  store when a provider does not expose a safe automated handoff.
