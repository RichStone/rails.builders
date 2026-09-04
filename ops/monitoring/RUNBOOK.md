# Production host metrics

The Honeybadger CLI reports host CPU usage, load averages, memory usage, and
filesystem capacity every 60 seconds. It sends no application logs, process
names, container names, or personal data, and it opens no inbound port.

## Install

Copy this directory to the production host. Enter the existing Rails Builders
Honeybadger project API key without putting it in shell history, then run the
installer:

```sh
read -rsp 'Honeybadger project API key: ' HONEYBADGER_API_KEY
printf '\n'
export HONEYBADGER_API_KEY
sudo --preserve-env=HONEYBADGER_API_KEY ./install
unset HONEYBADGER_API_KEY
```

The installer verifies the pinned Honeybadger CLI release checksum, stores the
key in `/etc/rails-builders/monitoring` with mode `0600`, and enables the
`rails-builders-host-metrics.service`. Later installer runs preserve the key.

Verify the service locally:

```sh
systemctl status rails-builders-host-metrics.service
journalctl -u rails-builders-host-metrics.service --since today
```

In Honeybadger Insights, select the project's default stream and query the
latest host values:

```text
fields @ts, used_percent::float, load_avg_1::float, load_avg_5::float, load_avg_15::float
| filter event_type::str == "report.system.cpu"
| sort @ts desc
| limit 20
```

Change the event type to `report.system.memory` or `report.system.disk` for RAM
or filesystem usage. The public `/up` endpoint remains only a liveness probe;
resource details belong in the authenticated monitoring dashboard.

## Hetzner status

The daily audit can check the single server in this Hetzner project without
exposing its name, address, or provider identifiers. Generate a project-scoped
API token with **Read** permission, then store it locally without echoing it:

```sh
ops/monitoring/store-hetzner-token
```

Run the sanitized check with:

```sh
ops/monitoring/hetzner-status
```

The checker reads only aggregate server state, backup freshness, and protection
flags. Its credential is stored in macOS Keychain under the repository-specific
service name `rails-builders-hcloud-readonly`; it is not written to the repository
or shared with other projects.
