# Production backup and restore drill

This bundle backs up the complete durable tree at `/srv/rails-builders/storage`.
The nightly job stops the one running Kamal web container, snapshots the four
SQLite databases and local uploads together, restarts the same container, waits
for `/up`, and then applies retention. Any failed step makes the systemd job
fail. An exit trap still attempts the restart and health check after an
interrupted or failed backup.

## Install

On the production host, install Docker first (normally via Kamal), plus `restic`,
`sqlite3`, `curl`, `jq`, `df` (`coreutils`), and `flock` (`util-linux` on
Ubuntu). Then copy this directory to the host and run:

```sh
sudo ./install
sudoedit /etc/rails-builders/backup
sudo chmod 0600 /etc/rails-builders/backup
```

Set `RESTIC_REPOSITORY`, `RESTIC_PASSWORD`, and only the credentials required by
the chosen Restic backend. For example, Backblaze B2 uses `B2_ACCOUNT_ID` and
`B2_ACCOUNT_KEY`; an S3-compatible backend uses the `AWS_*` variables. Keep all
real credentials only in `/etc/rails-builders/backup`. The installer never
overwrites that file on a later run. Set `BACKUP_CHECK_IN_URL`,
`DISK_USAGE_CHECK_IN_URL`, `RESTIC_CHECK_IN_URL`, and `RESTORE_CHECK_IN_URL` to
separate Honeybadger check-ins when they are available; each URL is called only
after its job succeeds, so a failed or missing run alerts.

Initialize a new repository using the same root-readable EnvironmentFile:

```sh
sudo systemd-run --unit=rails-builders-restic-init --wait --pipe \
  --property=Type=oneshot \
  --property=EnvironmentFile=/etc/rails-builders/backup \
  /usr/bin/restic init
```

## Prove recovery before scheduling

Run one backup only after the production container and health endpoint are live:

```sh
sudo systemctl start rails-builders-backup.service
sudo systemctl status rails-builders-backup.service
sudo journalctl -u rails-builders-backup.service --since today
```

Then restore the latest tagged snapshot to a temporary directory. Before it
creates that directory or restores any data, the drill uses `restic stats` to
measure the snapshot and refuses to continue unless the scratch filesystem has
more free bytes than the restore size plus the larger of 1 GiB or 10% headroom.
The drill checks every `production*.sqlite3` database with
`PRAGMA integrity_check`, confirms all four expected databases exist, and
verifies every Active Storage blob referenced by the primary database exists
with the recorded byte size. The temporary copy is deleted on exit and
production data is never modified.

```sh
sudo systemctl start rails-builders-restore-smoke.service
sudo systemctl status rails-builders-restore-smoke.service
sudo journalctl -u rails-builders-restore-smoke.service --since today
```

After both jobs pass, enable the hourly capacity check, nightly backup, weekly
repository check, and monthly restore verification:

```sh
sudo systemctl enable --now rails-builders-backup.timer
sudo systemctl enable --now rails-builders-capacity-check.timer
sudo systemctl enable --now rails-builders-restic-check.timer
sudo systemctl enable --now rails-builders-restore-smoke.timer
sudo systemctl list-timers 'rails-builders-*'
```

The capacity service fails when the filesystem containing
`/srv/rails-builders/storage` reaches 65% usage, before the 70% operational
ceiling (configurable with
`DISK_USAGE_LIMIT_PERCENT`). Retention is 7 daily, 5 weekly, and 12 monthly
tagged snapshots. Monitor failed systemd units and keep the Restic password in a
second secure location; without that password, an off-host repository cannot be
restored.

## Recovery

First run `rails-builders-restore-smoke.service` against the intended snapshot
(`RESTORE_SNAPSHOT` can be set in the EnvironmentFile) and inspect its journal.
For an actual recovery, restore into a new temporary or replacement-host path,
verify it there, stop the application, and only then replace
`/srv/rails-builders/storage`. Never restore over a running SQLite application
or overwrite newer production state merely to roll back application code.
