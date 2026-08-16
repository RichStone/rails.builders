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

## Email and optional integrations

- `RESEND_API_KEY` is required for production delivery of transactional email through Resend. The `rails.builders` sending domain must be verified in Resend.
- `CLICKFUNNELS_API_TOKEN` enables newsletter contact/tag reconciliation after a person separately opts in, confirms the newsletter email, and verifies their Rails Builders email. Without it, the admin UI reports `missing configuration`; registration still works.
- `HONEYBADGER_API_KEY` enables production error reporting.
- `APP_HOST` controls links in production email and defaults to `rails.builders`.

Slack membership is deliberately manual in v1. Administrators can track its status for each builder. Live-session attendance, timers, and Three Strikes are outside v1.
