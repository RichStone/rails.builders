# Rails Builders agent instructions

## Development

- Use the shared Loop Labs skills for development: `$implement` for bounded implementation, `$karpathy-guidelines` and `$ponytail` while coding, and `$code-review` plus `$ponytail-review` for the final diff. Read the installed skills rather than copying them into this repo.
- For that review, use the task's starting commit as the default base and the approved request plus settled chat decisions as the specification. A separate ticket or spec document is not required.
- Do not add unit-test files or cases, including new cases in existing unit-test files, unless the user explicitly requests an exception. Maintain existing tests when behavior changes; remove only obsolete coverage, never coverage that exposes a failure.
- Do not add explanatory code comments or docstrings unless the user explicitly requests them. Keep existing comments accurate, remove obsolete ones, and express intent through clear names and structure.
- Verify changes with existing suites and real behavior checks. Add integration or system coverage only when it protects a meaningful public workflow; do not disguise isolated unit tests as integration tests. HTTP request/response and browser flows are approved seams for `$tdd` without asking again.
- Apply these defaults to new code and existing code. Do not sweep the repository to delete useful tests or comments.

## Delivery

- When a change fully meets the requirements, has no open questions, passes all relevant tests, and passes a `$ponytail` review with no unaddressed findings, commit it and push it directly to `main` for automatic deployment without asking for further approval.
- Before pushing, incorporate the current `origin/main` without overwriting unrelated work and rerun any checks affected by the integration.
- Repair failed checks, review findings, integration conflicts, CI failures, and deployment failures needed to complete the change, including failures exposed by incorporating current `main`. Diagnose the cause, make the smallest safe fix, rerun the affected checks, and continue without asking for approval. Never bypass or weaken a check to ship.
- After pushing, monitor CI and the automatic deployment through production health verification. Stop and report only when safe completion requires missing user information or an action outside the approved scope, such as a destructive production change or a security/privacy policy decision.
- This standing authorization remains active until Rich changes or revokes it.
