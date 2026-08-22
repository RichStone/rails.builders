# Rails Builders

The Rails Builders home, enrollment queue, and small membership tool. It runs on Rails 8.1 with SQLite, Hotwire, Active Storage, and the Solid adapters—no Node runtime or front-end framework required.

## Local setup

```sh
bin/setup
bin/rails db:seed
bin/dev
```

Open [http://localhost:3000](http://localhost:3000). In development, transactional emails open in the browser through Letter Opener. The check-email screen also exposes the just-created verification link so every login and enrollment state can be exercised without an email service.

The seed is idempotent and creates the Continuous cohort, twenty private OG cards, and Rich’s public administrator/facilitator profile.

## ChatGPT worktrees

The ChatGPT desktop app discovers the committed [`.codex/environments/environment.toml`](.codex/environments/environment.toml), so there is no setup script to paste into the app. If this project was previously set to **No local environment**, select the committed default without opening settings:

```sh
bin/worktree configure-chatgpt
```

The selected app configuration stays pointed at the tracked file, so future Git changes synchronize automatically. When ChatGPT creates a worktree, it runs:

```sh
bin/worktree setup
```

Each worktree receives its own stable, available localhost port in `.worktree.env`. Its SQLite development/test databases, uploads, logs, temp files, and PID file are already isolated because they live inside that worktree. The setup checks dependencies, prepares the database, clears logs/temp files, and finishes with the URL, resource paths, and quick commands.

Use the **Start Rails**, **Stop Rails**, **Test**, and **Worktree info** actions in the ChatGPT toolbar, or run:

```sh
bin/worktree start
bin/worktree stop
bin/worktree info
bin/rails test
```

Ignored machine-local files named in [`.worktreeinclude`](.worktreeinclude)—currently only `.env.development`—are copied from the source checkout before setup when they exist. Secrets such as `config/master.key` stay in the source checkout unless an operator deliberately provides them. Never put the generated `.worktree.env` in `.worktreeinclude`; every worktree must retain its own port.

## Verification

```sh
bin/rails test
bin/rubocop
bin/brakeman --quiet --no-pager --exit-on-warn --exit-on-error
bin/bundler-audit
bin/importmap audit
RAILS_ENV=production SECRET_KEY_BASE_DUMMY=1 bin/rails assets:precompile
```

`bin/ci` runs the full local pipeline, including a seed replant after the test suite.

## Production deployment

Production runs as one Kamal web role. Puma also runs Solid Queue, and the four
SQLite databases plus Active Storage share the persistent host directory
`/srv/rails-builders/storage`.

Once the server architecture and IP address are known, copy `.env.example` to
the ignored `.env`, replace every production value, and export it before using
Kamal:

```sh
set -a
. ./.env
set +a

ssh root@"$KAMAL_HOST" "install -d -o 1000 -g 1000 /srv/rails-builders/storage"
bin/kamal config
bin/kamal setup
```

`KAMAL_BUILD_ARCH` must match the purchased server (`arm64` or `amd64`). The
default image repository is `docker.io/richwhale/rails-builders`; the registry
password must be a Docker Hub access token with Read & Write permission. Keep
`KAMAL_PROXY_SSL=false` for the first pre-DNS deployment and smoke-test the new
host directly:

```sh
curl --fail --header 'Host: rails.builders' "http://$KAMAL_HOST/up"
```

After both apex and `www` DNS records resolve to the server, set
`KAMAL_PROXY_SSL=true` and deploy again so Kamal Proxy can obtain certificates.
Do not run
the first deployment until an off-server backup target and restore check have
been chosen for `/srv/rails-builders/storage`. Install and prove the supplied
[backup and restore bundle](ops/backup/RUNBOOK.md) before calling recovery ready.

## Email and integrations

- `RESEND_API_KEY` is required for production delivery of transactional email through Resend. The `rails.builders` sending domain must be verified in Resend.
- Production ClickFunnels configuration lives under `clickfunnels` in encrypted Rails credentials: `api_token`, `base_url`, `workspace_id`, `newsletter_tag_id`, and optional `newsletter_tag_public_id`. The newsletter job runs only after a person separately opts in, confirms the newsletter email, and verifies their Rails Builders email. Missing production configuration is visible to Administrators without breaking registration.
- Development and test make no ClickFunnels requests by default and record `skipped_local`. A deliberate local smoke run may set `CLICKFUNNELS_SMOKE_TEST_PROFILE=test-only`; that mode is bound to the isolated Test Only workspace and rejects every other profile. Pass its token through the inherited descriptor named by `CLICKFUNNELS_API_TOKEN_FD` so it never enters a project file, command argument, or exported environment variable.
- `HONEYBADGER_API_KEY` enables production error reporting.
- `APP_HOST` controls links in production email and defaults to `rails.builders`.

### Google Calendar and Meet

Sessions use a dedicated secondary Google Calendar owned by the Program’s main facilitator. Every timed event within the Program dates becomes a session, recurring events are expanded into their occurrences, all-day events are ignored, and Google Calendar remains the schedule source of truth. Create the recurring session event—including its Google Meet conference—on that calendar before connecting it in Administration.

Create a Google Cloud OAuth web client, enable the Google Calendar API and Google Meet REST API, and register this exact production redirect URI:

```text
https://rails.builders/admin/calendar_connection/callback
```

Set `GOOGLE_OAUTH_CLIENT_ID` and `GOOGLE_OAUTH_CLIENT_SECRET`, or add `google_workspace.client_id` and `google_workspace.client_secret` to encrypted Rails credentials. If `APP_HOST` is not `rails.builders`, register the matching HTTPS callback. Configure the OAuth consent screen and complete Google’s verification requirements before production use. The integration requests read-only Calendar-list access, read-only access to events on calendars the account owns, and read-only access to Meet spaces the account can access; application queries are narrowed to the selected Program calendar and its synced Meet links. The connected Google email must exactly match the main facilitator’s Rails Builders email, and only secondary calendars owned by that account can be selected.

Turn on Meet transcription or automatic transcription for the recurring meeting in Google Workspace. The read-only Rails Builders integration imports the resulting artifact but does not change the meeting’s transcription settings.

Calendar sync runs hourly and can also be queued by a facilitator or Administrator. Active-session maintenance runs every minute. Google Meet transcript import uses adaptive retries from the five-minute recurring job and stops after a final attempt at 24 hours. OAuth tokens, Meet links, Google transcript resource identifiers, and transcript content are encrypted in the application database.

Slack membership is deliberately manual in v1. Administrators can track its status for each builder. Sessions include Calendar-backed scheduling, shared live timers, attendance, speaker order, and read-only transcripts. Three Strikes remains outside v1.
