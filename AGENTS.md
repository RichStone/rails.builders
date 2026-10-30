# Rails Builders agent instructions

## Delivery

- When a change fully meets the requirements, has no open questions, passes all relevant tests, and passes a `$ponytail` review with no unaddressed findings, commit it and push it directly to `main` for automatic deployment without asking for further approval.
- Before pushing, incorporate the current `origin/main` without overwriting unrelated work and rerun any checks affected by the integration.
- Repair failed checks, review findings, integration conflicts, CI failures, and deployment failures needed to complete the change, including failures exposed by incorporating current `main`. Diagnose the cause, make the smallest safe fix, rerun the affected checks, and continue without asking for approval. Never bypass or weaken a check to ship.
- After pushing, monitor CI and the automatic deployment through production health verification. Stop and report only when safe completion requires missing user information or an action outside the approved scope, such as a destructive production change or a security/privacy policy decision.
- This standing authorization remains active until Rich changes or revokes it.
