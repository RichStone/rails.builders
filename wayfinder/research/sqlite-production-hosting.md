# Production Hosting for Rails Builders on SQLite

- Researched: 2026-08-22
- Scope: one Rails 8.1 host using four local SQLite databases (primary, cache, queue, and cable), Solid Queue under Puma, and local Active Storage
- Priority order: durable and testable recovery, low monthly cost, EU/GDPR posture, operational simplicity, then future horizontal scaling
- Evidence: first-party provider, Rails, SQLite, Kamal, Restic, Litestream, and Turso documentation only

## Decision

Deploy one **Hetzner CX23 in Nuremberg with Kamal**, put the whole persistent tree at `/srv/rails-builders/storage` on the server's root disk, enable Hetzner's daily server backups and deletion protection, and run an **application-quiesced nightly Restic backup to a Backblaze B2 EU-Central bucket**.

This is the best present fit because it keeps the application's native `sqlite3` and local-file design unchanged, provides 4 GB RAM and 40 GB NVMe for about half the cost of a comparable PaaS, and makes the complete state—four databases plus uploads—portable to a replacement machine. Hetzner says local cloud-server storage uses RAID 10, while its optional server backup keeps seven daily full-disk copies ([cloud storage reliability](https://www.hetzner.com/cloud/), [backup behavior](https://docs.hetzner.com/cloud/servers/backups-snapshots/overview/)). Kamal directly supports bind mounts and deploys a new container behind its proxy after a health check ([Kamal volumes](https://kamal-deploy.org/docs/configuration/overview/), [deploy sequence](https://kamal-deploy.org/docs/commands/deploy/)). Solid Queue officially supports SQLite and the Puma plugin used by single-server Rails deployments ([Solid Queue](https://github.com/rails/solid_queue#puma-plugin)).

Backblaze is the preferred Restic target, rather than Hetzner Object Storage, for two reasons:

1. it is a separate provider and account, reducing the common-mode risk of a Hetzner account or control-plane incident; and
2. B2's first 10 GB are free and usage above that starts at $6.95/TB/month, whereas one Hetzner Object Storage bucket activates a €6.49/month account-wide base charge even for a tiny repository ([B2 pricing](https://www.backblaze.com/cloud-storage/pricing), [Hetzner Object Storage pricing model](https://docs.hetzner.com/storage/object-storage/overview/), [Hetzner current product price](https://www.hetzner.com/storage/object-storage/)).

Select B2's EU-Central account region, which stores the data in Amsterdam, and execute its DPA. Backblaze states that account data remains in the selected region unless the customer directs otherwise, and its DPA covers GDPR-protected stored files ([B2 regions](https://www.backblaze.com/docs/cloud-storage-data-regions), [B2 DPA](https://www.backblaze.com/company/policy/dpa-for-eea-eu-residents)). Restic encrypts and authenticates repository contents client-side; the repository password must also be kept outside the server ([Restic repository and password](https://restic.readthedocs.io/en/stable/030_preparing_a_new_repo.html), [encryption design](https://restic.readthedocs.io/en/stable/070_encryption.html)).

If adding a Backblaze account would delay launch, use a private Hetzner Object Storage bucket in Helsinki as the deploy-day fallback. Hetzner officially documents Restic over its S3-compatible endpoint, and Helsinki separates the backup from a Nuremberg server at the data-center level ([Hetzner Restic guide](https://docs.hetzner.com/storage/object-storage/howto-backups/restic/), [Object Storage locations and redundancy](https://docs.hetzner.com/storage/object-storage/faq/general/)). The tradeoff is the €6.49 base price and the same-provider/account failure domain.

## Expected monthly cost

Prices below are list prices checked on 2026-08-22 and exclude VAT, traffic overages, domain/email/monitoring services, and backup growth caused by retained historical versions.

| Chosen component | Monthly cost | Notes |
|---|---:|---|
| Hetzner CX23 | €5.49 | 2 shared x86 vCPU, 4 GB RAM, 40 GB NVMe after the 15 June 2026 price change ([price notice](https://docs.hetzner.com/general/infrastructure-and-availability/price-adjustment/)) |
| Primary IPv4 | €0.50 | IPv6 remains free ([Primary IP pricing](https://docs.hetzner.com/cloud/servers/primary-ips/overview/)) |
| Hetzner daily backup | about €1.10 | 20% of the server price; seven rolling daily slots ([billing FAQ](https://docs.hetzner.com/cloud/billing/faq/)) |
| Backblaze B2 EU | $0 initially | First 10 GB free; then $6.95/TB/month, with restore egress free up to 3x average stored data ([B2 pricing](https://www.backblaze.com/cloud-storage/pricing)) |
| **Expected starting total** | **€7.09/month plus VAT** | B2 will become a small usage charge as retained data exceeds 10 GB |

Cost-optimized Hetzner plans can have limited inventory. If CX23 is unavailable, CAX11 is the next choice only after an `arm64` production-image boot test; it has the same 4 GB/40 GB shape at €5.99 before IPv4 and backups. Do not jump automatically to the current €19.49 CPX22: at that point the PaaS alternatives deserve re-evaluation ([current Hetzner price notice](https://docs.hetzner.com/general/infrastructure-and-availability/price-adjustment/)).

Using Hetzner Object Storage instead of B2 raises the starting total to about **€13.58/month plus VAT**: €5.49 server + €0.50 IPv4 + €1.10 backup + €6.49 Object Storage. The Object Storage base includes up to 1 TB storage and 1 TB egress, so it is good value only if the account will use more of that allowance. Internal `eu-central` transfer is free ([Object Storage overview](https://docs.hetzner.com/storage/object-storage/overview/)).

## Why the backup must quiesce the app

Restic should not copy live SQLite files blindly. SQLite warns that a filesystem copy made during a transaction can mix old and new pages and be corrupt; safe alternatives are the SQLite backup API, `VACUUM INTO`, `sqlite3_rsync`, or copying while no transaction is active ([SQLite corruption guidance](https://www.sqlite.org/howtocorrupt.html#_backup_or_restore_while_a_transaction_is_active), [SQLite online backup API](https://www.sqlite.org/backup.html)).

This application has four independent databases and local uploads in one storage tree. Per-database online copies would make each database valid, but would not produce one common point in time with the uploaded files. The simplest complete-MVP policy is therefore:

1. acquire a host-level `flock` so two backups cannot overlap;
2. gracefully stop the application container, allowing Puma/Solid Queue to finish or release work;
3. run `restic backup /srv/rails-builders/storage`;
4. restart the application and require the health endpoint to pass;
5. only after a successful snapshot, apply `--keep-daily 7 --keep-weekly 5 --keep-monthly 12 --prune`; and
6. alert on backup, restart, health-check, or prune failure.

That accepts a short scheduled interruption in exchange for one coherent, portable snapshot of databases and files. The resulting stated recovery-point objective is **at most 24 hours** for all durable application state. Hetzner's automatic disk backup is a fast second recovery path, but its documentation does not promise an application-consistent SQLite snapshot, so it is not the primary data backup.

Run `restic check` regularly and restore to a temporary directory monthly; Restic explicitly recommends repository checks and documents full snapshot restores ([Restic quickstart](https://restic.readthedocs.io/en/stable/010_introduction.html)). For a restore drill, run `PRAGMA integrity_check` on all four restored databases and verify representative Active Storage blobs. Perform one full replacement-server restore before treating the backup system as complete. A backup that has never restored successfully is only an assumption.

Litestream can later reduce database RPO from one day to seconds by asynchronously copying SQLite WAL changes to S3 and supports multiple database paths ([how Litestream works](https://litestream.io/how-it-works/), [multi-database configuration](https://litestream.io/reference/config/)). It is not a substitute for Restic here because it does not back up local Active Storage or make the four databases and uploads one atomic unit.

## Alternatives evaluated

### Fly.io: good SQLite ergonomics, weaker single-volume durability

A Frankfurt `shared-cpu-1x` with 2 GB RAM is currently $12.34/month, and a 10 GB volume is $1.50/month, for about **$13.84/month** before transfer. Automatic daily volume snapshots retain five days by default (configurable to 60); the first 10 GB of snapshot data is free ([Fly compute and volume pricing](https://fly.io/docs/about/pricing/)).

The problem is the primary volume. Fly documents that a volume exists on one physical server, attaches to one Machine, is not automatically replicated, and can be lost with that drive. Fly recommends at least two Machines and two volumes, plus application/database replication; it also says its daily snapshots should not be the primary backup plan ([Fly volume considerations](https://fly.io/docs/volumes/overview/)). Two 2 GB Machines and two 10 GB volumes would start around $27.68/month and require LiteFS or another replication design. Fly's own LiteFS documentation now warns that autoscaling or autostop can elect stale data and cause rollback/data loss if configured incorrectly ([LiteFS warning](https://fly.io/docs/litefs/)).

Fly can run the Puma/Solid Queue process and has Frankfurt, Amsterdam, Paris, and Stockholm regions plus a signable GDPR DPA ([regions](https://fly.io/docs/reference/regions/), [DPA availability](https://fly.io/documents)). It is a reasonable fallback if unmanaged-server work is unacceptable, but it is neither cheaper nor more durable for this deliberately single-writer deployment once proper replication and independent backup are included.

### Render: explicitly discourages this production shape

A comparable Standard web service is $25/month for 2 GB RAM; a 10 GB persistent disk adds $2.50 at $0.25/GB/month, totaling **$27.50/month** ([Render pricing](https://render.com/pricing)). Render offers Frankfurt and a GDPR DPA ([regions](https://render.com/docs/regions), [DPA](https://render.com/dpa)).

However, Render's official Rails 8 guide says production Rails apps on Render should not use SQLite. A disk can attach to only one service instance, disables zero-downtime deploys, is unavailable to pre-deploy commands and one-off jobs, and prevents horizontal scaling. Although Render creates daily disk snapshots kept at least seven days, its disk documentation warns not to use a disk restore for custom-database recovery because the result may be corrupt ([Rails 8 guide](https://render.com/docs/deploy-rails-8), [persistent disk limits and backups](https://render.com/docs/disks)). In-process Solid Queue works around the separate-worker disk limitation, but it does not fix the unsupported backup seam. Reject for this MVP.

### Railway: simplest managed-volume option, but constrained and less portable

Railway's Hobby plan is a $5 minimum that counts toward usage. Current metering is $10/GB-month of average RAM, $20/vCPU-month of average CPU, and $0.15/GB-month of used volume storage ([Railway pricing](https://docs.railway.com/pricing/plans)). For illustration—not a quote—1 GB average RAM + 0.05 average vCPU + 5 GB storage is about **$11.75/month**; 2 GB + 0.1 vCPU + 5 GB is about **$22.75/month**. Actual Rails memory and CPU determine the bill.

Railway has the strongest built-in SQLite-specific wording of these PaaS options: volume backups explicitly include SQLite, with daily copies kept six days, weekly copies one month, and monthly copies three months. Backups are incremental and charged at the normal volume rate ([Railway backups](https://docs.railway.com/volumes/backups)). But the Hobby volume ceiling is 5 GB; one service can have only one volume; replicas cannot use volumes; and volume-backed deploys have brief downtime. Backups restore only inside the same project/environment, wiping a volume deletes all its backups, and the feature is still described as under development ([Railway volume limits](https://docs.railway.com/volumes/reference), [backup caveats](https://docs.railway.com/volumes/backups)). An external export is still required for real provider/account portability.

Railway offers an Amsterdam region and a GDPR DPA, but the DPA says its primary processing operations occur in the United States and US transfer is necessary even where local data-storage options exist ([regions](https://docs.railway.com/deployments/regions), [DPA](https://railway.com/legal/dpa)). Railway is the operational-simplicity runner-up, not the durability/cost winner.

### Turso/libSQL and Litestream: useful SQLite-native tools, not a better immediate host

Turso is the clearest managed SQLite-native candidate. Its Developer plan is $4.99/month with 9 GB storage and ten days of commit-level point-in-time recovery; it publishes eleven-nines durability backed by S3/S3 Express and has an Ireland region ([pricing](https://turso.tech/pricing), [PITR](https://docs.turso.tech/features/point-in-time-recovery), [durability](https://docs.turso.tech/cloud/durability), [locations](https://docs.turso.tech/api-reference/locations/list)).

It is not a drop-in host for this MVP. Turso requires replacing Rails' native `sqlite3` adapter with `libsql_activerecord`, and Turso labels its Rails integration **technical preview** ([Rails integration](https://docs.turso.tech/sdk/activerecord/guides/rails)). The app would still need compute and durable/object storage for uploads, and all four Solid databases would need compatibility testing. Turso is worth a future prototype if single-server SQLite becomes the scaling limit, not a launch-day migration.

Litestream is a mature SQLite disaster-recovery sidecar rather than a hosting platform. It improves database RPO but does not solve local uploads, whole-tree consistency, compute, TLS, or host operations. It complements the chosen design after launch; it does not replace it.

## Launch configuration implied by this decision

- One x86 CX23 in Nuremberg, Ubuntu LTS, IPv4 + IPv6, Hetzner firewall allowing SSH only from the operator's current trusted source where practical and public 80/443, deletion protection, and daily backups.
- No attached Hetzner Volume initially. Keep `/srv/rails-builders/storage` on the 40 GB root disk so the provider's full-disk backup includes it. Hetzner explicitly excludes attached Volumes from server backups ([backup scope](https://docs.hetzner.com/cloud/servers/backups-snapshots/overview/)).
- One Kamal web role with `/srv/rails-builders/storage:/rails/storage`, `SOLID_QUEUE_IN_PUMA=1`, an HTTPS proxy, and a real `/up` health check. Keep queue process/thread counts conservative until memory is measured; Solid Queue's default Puma mode forks and therefore uses additional memory ([Solid Queue Puma mode](https://github.com/rails/solid_queue#running-as-a-fork-or-asynchronously)).
- A systemd timer for the quiesced Restic backup, with the Restic repository password and S3 key readable only by root. Keep another copy of the repository password outside Hetzner and outside B2.
- Disk-usage alerting before 70%, backup-age/failure alerting, and a documented replacement-server restore command. The primary disk grows only by resizing to a larger server plan, so capacity must be watched ([Hetzner disk resizing](https://docs.hetzner.com/cloud/servers/faq/#how-can-i-increase-the-primary-disk-of-my-cloud-server)).
- Execute the applicable DPAs. Hetzner states that cloud servers selected in Nuremberg/Falkenstein/Helsinki and their backups remain within the EU ([Hetzner data protection](https://docs.hetzner.com/general/company-and-policy/data-protection-at-hetzner/)).

This remains a single-host service: host maintenance or loss causes downtime while a new host is restored. The design optimizes for low cost and recoverability, not high availability. If the required availability changes, the next decision should compare a tested LiteFS pair against moving the primary and Solid Queue to managed PostgreSQL; merely adding a second web container cannot safely share these local SQLite databases.
