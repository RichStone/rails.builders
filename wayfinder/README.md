# Local Wayfinder Tracker

This directory is the issue-tracker fallback for an as-yet uninitialized repository.

- The map is [Find the Rails Builders Replacement](rails-builders-map.md).
- Each file in `tickets/` is a child issue; its title is its human-readable identity.
- Claim a ticket by replacing `Assignee: unassigned` before doing any work.
- The frontier is every `open`, `unassigned` ticket whose linked blockers are all `closed`, sorted by `Order`.
- Put substantive answers in a resolution comment under `resolutions/`; research evidence belongs under `research/`.
- On resolution, close the ticket and append only a one-line linked gist to the map's Decisions-so-far.
- Resolve at most one non-research ticket per session.
