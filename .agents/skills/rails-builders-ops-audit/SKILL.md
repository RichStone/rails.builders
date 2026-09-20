---
name: rails-builders-ops-audit
description: Audit Rails Builders production health, security, and privacy, and safely triage Dependabot PRs. Use for scheduled or manual health and maintenance sweeps in this repository; do not use for feature development.
---

# Rails Builders Security and Health Audit

Keep Rails Builders healthy without leaking private application, customer, or infrastructure data. The repository is public, as are its commits, pull requests, and GitHub Actions logs.

## Public-repository safety boundary

Treat all non-public data as sensitive, including credentials, environment values, provider and account identifiers, host addresses, user records, names, email addresses, IDs, membership state, request data, authentication events, and error payloads.

- Never print, paste, commit, upload, or put sensitive values in commands, URLs, branch names, commit messages, PR text, CI annotations, screenshots, or audit reports.
- Never run broad-output commands such as `env`, `printenv`, an unrestricted `docker inspect`, raw database dumps, user-table queries, or unfiltered production log commands.
- Read secrets only through the existing ignored environment, credential store, or provider integration. Test presence or behavior without echoing values.
- Query production databases only for schema/version state, integrity checks, and aggregate operational counts. Never inspect application rows during this audit.
- Reduce authentication logs to counts and trends. Never show source IPs, attempted usernames, request paths, headers, or payloads.
- Reduce Honeybadger and provider results to status, counts, severity, and the smallest safe next action. Do not reproduce stack traces, request context, user context, or provider identifiers.
- Keep temporary artifacts outside the repository and remove them when finished. Before any commit or push, inspect the exact staged diff for accidental secrets, PII, internal addresses, or raw logs.

If a check cannot be performed without exposing sensitive data, skip it and report only that the check was unavailable.

## Authorization boundary

The repository owner grants standing authorization for scheduled and manual audits to fetch `origin` and rebase a clean local `main` onto `origin/main` before auditing. This authorization applies only to the clean audit worktree on `main`; it does not permit switching branches, autostashing, rewriting divergent history, or disturbing local work.

The repository owner also grants standing authorization to update and squash-merge Dependabot PRs that pass every gate in this skill. This authorization is limited to the guarded Dependabot workflow and its three-merge-per-sweep cap.

Everything else remains read-only. This skill does not authorize a manual deploy, reboot, package installation, credential or account change, firewall or DNS change, provider mutation, unrelated code edit, non-Dependabot PR update, or non-Dependabot merge.

## Preserve the workspace

Start with `git status --short --branch` and record the current commit, then fetch `origin`. If the current branch is `main`, the workspace is clean, and local history has not diverged from `origin/main`, run `git rebase origin/main` before reading repository configuration or running checks. This keeps project-scoped integrations, scripts, and audit policy current. If the rebase conflicts, abort it immediately and use a temporary worktree based on `origin/main`.

If the workspace is dirty, is on another branch, or has diverged from `origin/main`, do not switch, reset, clean, stash, merge, overwrite, rebase, or commit local work. Run the audit from a temporary worktree based on `origin/main`, and remove that worktree when finished. Use a separate temporary worktree based on the remote PR head when dependency verification requires its checkout.

## Recent main change review

Before checking production, inspect the commits and exact diff that arrived during the initial sync. If the worktree was already current, inspect the latest commit. Review only for newly introduced, evidence-backed concerns in these areas:

- security boundaries such as authentication, authorization, input validation, secret handling, sensitive-data exposure, and dependency or deployment configuration;
- privacy and compliance such as new data collection, sharing, retention, tracking, consent, or a mismatch with the public privacy notice;
- obvious performance misgivings such as an unbounded query or loop, an evident N+1 query, a blocking external call on a request path, or unbounded payload or storage growth.

Do not turn this into optimization, profiling, speculative hardening, or a broad code review. Report only concrete findings tied to the new diff. A security or privacy finding, or an obvious performance regression that makes deployment unsafe, is a stop condition for dependency mutations.

## Production audit

Collect only the minimum evidence needed to determine status:

1. Verify the public homepage, `/up`, privacy page, TLS, and the `www` redirect with read-only requests.
2. Confirm the deployed image matches the latest green `main` SHA and inspect the latest GitHub Actions CI/deploy result.
3. Check for failed systemd units, a pending reboot, pending security updates, disk pressure, memory pressure, and an active `rails-builders-host-metrics.service`.
4. Confirm effective SSH policy remains key-only with the repository's hardened settings. Report failed-authentication counts and seven-day trend only.
5. Check externally reachable ports and report only whether the expected web and SSH exposure changed.
6. Run `PRAGMA quick_check` against the primary, cache, queue, and cable SQLite databases. Report one status per database, never contents.
7. Report aggregate Solid Queue failed-execution and recurring-task counts.
8. Check for potential spam signups since the previous completed audit using only the application's aggregate hourly `SignupAbuse` counters. Take the prior audit time from this task when available and round it down to the hour to match the buckets; otherwise use the preceding 24 hours and label that fallback. Report new-registration and verification totals, grouped bot/form/rate-limit signals, and whether an existing configured hourly alert threshold was crossed. Treat a registration/verification mismatch as a signal rather than proof, and never inspect accounts, emails, IPs, IDs, or event payloads or report cache keys. The counters expire after 48 hours, so report the interval as unavailable rather than widening the query when the previous audit is older.
9. If the optional repository backup bundle is installed, confirm its timers are active and its last backup, repository check, and restore smoke test are fresh. Do not treat the intentionally uninstalled optional bundle as a failure.
10. Use the first authenticated read-only Honeybadger capability available in this project, preferring the project-scoped MCP connection. Discover its current read tools instead of assuming fixed tool names, scope every query to Rails Builders, and skip rather than guess between projects. Check connectivity, the count of unresolved production errors newly seen or recurring in the last 24 hours, active alarms, and whether CPU, memory, and disk events from the host metrics service are current. When the integration exposes uptime monitors or check-ins, include their aggregate status. Never fetch or report individual occurrences, stack traces, messages, request data, user context, or provider identifiers during the routine audit.
11. Run `ops/monitoring/hetzner-status` when its repository-scoped Keychain credential is available. Report only its aggregate status fields; never include provider identifiers or retry with a token from another project.

If an authenticated provider capability is unavailable, continue the independent health checks and report only which provider check was unavailable. Do not make a plugin or one exact MCP tool name a permanent dependency of this workflow.

Do not repair findings during the audit. A failed health check, database integrity failure, unexpected network exposure, or failed deployment is a stop condition: skip dependency mutations and report the smallest next action.

## Dependabot sweep

During every scheduled or manual audit, evaluate all open PRs whose author is `app/dependabot` and automatically handle each candidate that passes every gate below.

- Automatically handle patch updates and minor updates whose current major version is at least 1.
- Require the candidate branch to include current `main`, and require fresh success from every CI check.
- Inspect the exact diff and primary release notes. Accept only expected dependency or action-version files.
- Do not merge major updates, pre-1.0 minor updates, breaking notices, security-sensitive or ambiguous updates, Ruby/Rails/toolchain jumps, migrations, configuration or environment changes, unexpected files, or failed checks.
- Do not hand-edit a Dependabot branch or bypass checks.
- Squash-merge one candidate at a time, at most three per sweep.
- After each merge, wait for the resulting `main` CI and automatic Kamal deployment. Verify `/up` and the deployed SHA before considering another PR. Stop on the first failure; never manually deploy as a workaround.

## Output

Return a concise private audit summary:

- overall production status;
- sanitized check results and prioritized findings;
- the potential-spam assessment and interval;
- Dependabot PR numbers and actions taken or safe reasons for skipping them;
- any unavailable checks and the smallest next action.

Every mentioned issue, finding, blocker, skipped check, unavailable integration, or unresolved item must include at least one complete sentence of sanitized context explaining what was observed and why it matters. Never refer only to "previously reported findings" or similar shorthand; restate enough context for each report to stand on its own.

An all-clear should be short. Never include raw command output, raw logs, secrets, PII, internal addresses, or provider/account identifiers.
