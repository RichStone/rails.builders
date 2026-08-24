# Rails Builders agent instructions

## Delivery

- When a change fully meets the requirements, has no open questions, passes all relevant tests, and passes a `$ponytail` review with no unaddressed findings, commit it and push it directly to `main` for automatic deployment without asking for further approval.
- Before pushing, incorporate the current `origin/main` without overwriting unrelated work and rerun any checks affected by the integration.
- After pushing, monitor CI and the automatic deployment through production health verification. Stop and report any failed gate, conflict, CI failure, deployment failure, security or privacy concern, or destructive action that falls outside the approved change.
- This standing authorization remains active until Rich changes or revokes it.
