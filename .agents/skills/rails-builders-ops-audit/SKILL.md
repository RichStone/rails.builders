---
name: rails-builders-ops-audit
description: Audit Rails Builders production and safely triage Dependabot PRs. Use for scheduled or manual operational, security, privacy, and dependency-maintenance sweeps in this repository; do not use for feature development.
---

# Rails Builders Operations Audit

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

The audit is read-only by default. This skill does not authorize a deploy, reboot, package installation, credential or account change, firewall or DNS change, provider mutation, code edit, PR update, or merge.

Dependabot branch updates and merges are allowed only when the current user request or scheduled-task prompt explicitly authorizes them. Never infer that permission from this skill.

## Preserve the workspace

Start with `git status --short --branch`. Never reset, clean, stash, overwrite, or commit unrelated local work. If dependency verification needs a checkout and the current workspace is dirty, use a temporary worktree based on the remote PR head.

## Production audit

Collect only the minimum evidence needed to determine status:

1. Verify the public homepage, `/up`, TLS, and the `www` redirect.
2. Confirm the deployed image matches the latest green `main` SHA and inspect the latest GitHub Actions CI/deploy result.
3. Check for failed systemd units, a pending reboot, pending security updates, disk pressure, and memory pressure.
4. Confirm effective SSH policy remains key-only with the repository's hardened settings. Report failed-authentication counts and seven-day trend only.
5. Check externally reachable ports and report only whether the expected web and SSH exposure changed.
6. Run `PRAGMA quick_check` against the primary, cache, queue, and cable SQLite databases. Report one status per database, never contents.
7. Report aggregate Solid Queue failed-execution and recurring-task counts.
8. When authenticated access is available, check Honeybadger health plus unresolved-error count and confirm Hetzner backup and deletion-protection status without copying private details.

Do not repair findings during the audit. A failed health check, database integrity failure, unexpected network exposure, or failed deployment is a stop condition: skip dependency mutations and report the smallest next action.

## Dependabot sweep

When explicitly authorized, consider only open PRs whose author is `app/dependabot`.

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
- Dependabot PR numbers and actions taken or safe reasons for skipping them;
- any unavailable checks and the smallest next action.

An all-clear should be short. Never include raw command output, raw logs, secrets, PII, internal addresses, or provider/account identifiers.
