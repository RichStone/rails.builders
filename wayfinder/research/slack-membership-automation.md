# Slack Membership Automation Research

- Researched: 2026-08-09
- Evidence policy: first-party Slack API and administration documentation only
- Question: Can the Rails app reliably add an Active Builder to the relevant Slack workspace or channel and remove them when inactive, and what would that require?

## Decision-ready answer

**Yes for a dedicated channel when the person already has an active account in the workspace; only conditionally for workspace membership.** The standard Conversations API can add an existing workspace user to a public or private channel and remove that user later. The app must know the Slack user ID, hold the channel-specific scopes, and have sufficient channel access. The target cannot be `#general`, because Slack explicitly prohibits removing anyone from that channel. [`conversations.invite`](https://docs.slack.dev/reference/methods/conversations.invite/) requires the caller to be in the channel; [`conversations.kick`](https://docs.slack.dev/reference/methods/conversations.kick/) removes only that channel membership and documents `cant_kick_from_general`.

**No plan-independent API can reliably invite and later remove a person from a workspace.** Slack's supported programmatic routes are:

- Enterprise: the Admin Users API can invite a new person by email, assign an existing Enterprise user to a workspace, and remove a user from a workspace. These methods require an org-wide Enterprise app installation and an admin user token carrying `admin.users:write`. [Slack's Admin Users guide](https://docs.slack.dev/admins/managing-users/) and the [`admin.users.invite`](https://docs.slack.dev/reference/methods/admin.users.invite/), [`admin.users.assign`](https://docs.slack.dev/reference/methods/admin.users.assign/), and [`admin.users.remove`](https://docs.slack.dev/reference/methods/admin.users.remove/) references document those boundaries.
- Business+ or Enterprise: SCIM can create and deactivate accounts, using a privileged OAuth user token with the broad `admin` scope. On an Enterprise org, SCIM acts across the organization, not just one workspace. [Slack's SCIM guide](https://docs.slack.dev/admins/scim-api/) explicitly limits SCIM to Business+ and Enterprise and says Enterprise operations are org-wide.
- Free or Pro: Slack documents manual invitations and deactivations in its administration UI, but the Admin Users API is Enterprise-only and SCIM is Business+/Enterprise-only. An invitation link is not an enforcement mechanism: it can be used by anyone who obtains it, and invitations and invite links expire after 30 days. [Slack's invitation guide](https://slack.com/help/articles/201330256-invite-new-members-to-your-workspace), [deactivation guide](https://slack.com/help/articles/204475027-Deactivate-a-members-account), [Admin Users guide](https://docs.slack.dev/admins/managing-users/), and [SCIM guide](https://docs.slack.dev/admins/scim-api/) document these boundaries.

**Channel removal, workspace removal, and deactivation are materially different:**

- `conversations.kick` removes access to one conversation and leaves every other workspace/channel entitlement intact.
- Enterprise `admin.users.remove` removes the user from one workspace but leaves them in the Enterprise organization. [Slack's deactivation guide](https://slack.com/help/articles/204475027-Deactivate-a-members-account) makes this workspace/org distinction explicit.
- SCIM `DELETE /Users/{id}` deactivates the account. In a standalone Business+ workspace that is workspace-wide; in an Enterprise org it is org-wide. Deactivation removes the person from channels and signs them out; it does not delete their profile, messages, or files. [Slack's SCIM reference](https://docs.slack.dev/reference/scim-api/) defines `DELETE /Users/{id}` as deactivation, while the [deactivation administration guide](https://slack.com/help/articles/204475027-Deactivate-a-members-account) describes the user-visible effect.
- A guest expiration disables the guest account rather than merely removing it from the Rails Builders channel. Enterprise Admin APIs can set this on invitation or later with [`admin.users.setExpiration`](https://docs.slack.dev/reference/methods/admin.users.setExpiration/).

Therefore the safest feasible v1 is **desired-state sync for one dedicated, non-`#general` channel, without workspace invitation or account deactivation**, provided the workspace-specific prerequisites below are true. If Rails Builders owns a standalone Enterprise workspace, an expanded v1 can instead automate a Single-Channel Guest invitation and later workspace removal. If neither condition is true, workspace access should remain an explicit Administrator workflow.

## Capability and permission matrix

| Lifecycle action | Slack API | Token and scopes | Plan/admin constraints | Important semantics |
| --- | --- | --- | --- | --- |
| Find an existing workspace user by email | `users.lookupByEmail` | Bot or user token; `users:read.email` | The method says custom bot users cannot call it | A deactivated user returns `users_not_found`; use `users.list` to find deactivated users. Tier 3. [Reference](https://docs.slack.dev/reference/methods/users.lookupByEmail/) |
| Add an existing workspace user to a public channel | `conversations.invite` | Prefer bot token with `channels:write.invites`; the method also accepts `channels:manage`. User-token alternatives are documented. | Authenticated caller must already be a channel member; workspace policies still apply | Accepts Slack user IDs. Removed workspace users fail; an already-present user returns `already_in_channel`. Tier 3. [Reference](https://docs.slack.dev/reference/methods/conversations.invite/) |
| Add an existing workspace user to a private channel | `conversations.invite` | Prefer bot token with `groups:write.invites`; `groups:write` is also accepted | App/bot must be in the private channel and allowed to invite | A restricted guest may be denied; a Single-Channel Guest already at its maximum returns `ura_max_channels`. [Reference](https://docs.slack.dev/reference/methods/conversations.invite/) |
| Remove a user from a public channel | `conversations.kick` | Bot token: `channels:manage`; user token: `channels:write` | Caller needs permission; workspace settings can restrict the action | Cannot remove from `#general`; `not_in_channel` is an idempotent terminal state. Tier 3. [Reference](https://docs.slack.dev/reference/methods/conversations.kick/) |
| Remove a user from a private channel | `conversations.kick` | Bot or user token: `groups:write` | Caller/app must have private-channel access and permission | Removes only the conversation membership. [Reference](https://docs.slack.dev/reference/methods/conversations.kick/) |
| Admin-add a user to a channel | `admin.conversations.invite` | Admin **user** token; `admin.conversations:write` | Enterprise only; app installed org-wide by an Org Admin/Owner. The installer also needs an appropriate Channel Management role and public/private-channel grants | Useful if ordinary bot membership is undesirable, but much more privileged. Tier 2. [Reference](https://docs.slack.dev/reference/methods/admin.conversations.invite/) |
| Invite a new person to a workspace, optionally as a guest and into initial channels | `admin.users.invite` | Admin **user** token; `admin.users:write` | Enterprise only; OAuth initiated by Org Admin/Owner and app installed across the org | Requires email, workspace ID, and at least one channel ID. Supports Single-Channel Guest, Multi-Channel Guest, and guest expiration. Returns only `ok`, so the app must subsequently resolve and persist the Slack identity. Tier 2. [Reference](https://docs.slack.dev/reference/methods/admin.users.invite/) |
| Add/reinstate an existing Enterprise user to a workspace | `admin.users.assign` | Admin **user** token; `admin.users:write` | Enterprise only; same org-wide install requirements | Can reinstate a removed user and specify guest/channel options. It can also reactivate an org-deactivated user, so it is not a harmless retry without a state check. Tier 2. [Reference](https://docs.slack.dev/reference/methods/admin.users.assign/) |
| Remove a user from one Enterprise workspace | `admin.users.remove` | Admin **user** token; `admin.users:write` | Enterprise only; cannot modify a Primary Owner | User remains part of the org. Tier 2. [Reference](https://docs.slack.dev/reference/methods/admin.users.remove/) |
| Create/deactivate a whole Slack account | SCIM `POST /Users`, `DELETE /Users/{id}` | Privileged OAuth **user** token; broad `admin` scope | Business+: Owner/Admin can generate token. Enterprise: only Org Owner installs; Owner/Admin token holder must retain the role, and the app must be org-installed | Deactivation is workspace-wide on standalone Business+ and org-wide on Enterprise. [Guide](https://docs.slack.dev/admins/scim-api/) and [reference](https://docs.slack.dev/reference/scim-api/) |

Slack's `admin.*` scopes are user-token scopes, not bot-token scopes. Slack requires an Enterprise Admin API app to be authorized on the entire org rather than an individual workspace; the OAuth installation must be initiated by an Org Admin or Owner. [Slack's Admin Users guide](https://docs.slack.dev/admins/managing-users/) documents these installation requirements. SCIM has an additional durable-operator dependency: its token-generating account must remain an Owner/Admin, and a token can act only on accounts at the same or a lower permission level. [Slack's SCIM authentication guide](https://docs.slack.dev/admins/scim-api/) documents both restrictions.

## Guest-account constraints

Guests are available only on paid plans. Multi-Channel Guests are billed as regular members; Single-Channel Guests are free within Slack's documented allowance of five per paid active member and can access only one channel. Workspace Owners/Admins control Single-Channel Guest access and Multi-Channel Guest public-channel access. [Slack's guest-role guide](https://slack.com/help/articles/202518103-Understand-guest-roles-in-Slack) documents the plan, billing, and permission boundaries.

For Rails Builders, a Single-Channel Guest is the narrowest workspace-level entitlement if the program lives in one channel. Full automation of that role is nevertheless plan-dependent:

- Enterprise `admin.users.invite` can create a Single-Channel Guest directly and specify its sole channel and expiration.
- SCIM cannot fully provision a Single-Channel Guest; Slack says it must first be provisioned as a full user and then restricted through the admin UI. SCIM provisioning of Multi-Channel Guests is itself Enterprise-only. [Slack's SCIM limitations](https://docs.slack.dev/admins/scim-api/) and [SCIM schema reference](https://docs.slack.dev/reference/scim-api/) document these restrictions.
- A normal `conversations.invite` cannot move a Single-Channel Guest into a second channel; Slack returns `ura_max_channels`. That guest's sole-channel assignment is an Administrator concern unless Enterprise Admin APIs are available.

Slack Connect is a different membership model, with separate invitation/approval APIs and external-workspace identities. It should not be assumed equivalent to a guest or ordinary workspace member. If the Rails Builders channel is externally shared, the v1 boundary needs separate Slack Connect research; the standard invite method already documents external permission and cross-workspace failures. [`conversations.invite`](https://docs.slack.dev/reference/methods/conversations.invite/) lists `no_external_invite_permission`, `invitee_cant_see_channel`, and `org_user_not_in_team` among its errors.

## Identity matching and persistence

Use email only for initial discovery/invitation, then persist Slack's opaque identifiers:

1. Start from the app's verified Builder email.
2. For an existing active workspace user, call `users.lookupByEmail` with `users:read.email`.
3. Persist `(team_id, user_id)` as the stable local binding. Slack explicitly recommends those fields together as the unique key. On Enterprise, prefer and also retain `enterprise_user.id` when present. [Slack's user object reference](https://docs.slack.dev/reference/objects/user-object/) documents both recommendations.
4. For a new Enterprise invitation, persist a pending provisioning record keyed by normalized email, then resolve the Slack ID from the workspace user list and replace the email-only key. `admin.users.invite` returns only `{ "ok": true }`; Slack user objects expose `is_invited_user` for invited people who have not yet signed in. [`admin.users.invite`](https://docs.slack.dev/reference/methods/admin.users.invite/) and the [user object reference](https://docs.slack.dev/reference/objects/user-object/) provide those response shapes.
5. Never silently attach a different local Builder merely because an email was later reused. Slack emails can change, while the user ID binding is the durable identity. For an explicit self-service binding, Sign in with Slack returns verified email, team ID, and user ID through OpenID Connect. [Slack's Sign in with Slack guide](https://docs.slack.dev/authentication/sign-in-with-slack/) documents these claims.

`users.lookupByEmail` deliberately returns `users_not_found` for deactivated users. Reconciliation must retain the previously stored ID and, when necessary, use paginated `users.list` with `users:read` plus `users:read.email` to distinguish "never invited" from "deactivated". [Slack's lookup reference](https://docs.slack.dev/reference/methods/users.lookupByEmail/) prescribes that fallback.

SCIM can filter users by email, but duplicate-email provisioning fails even when the existing account is deactivated. The old account must be recovered/reactivated or manually changed; creating a second account is not a valid retry. [Slack's SCIM filter reference](https://docs.slack.dev/reference/scim-api/) supports email filters, and the [SCIM limitations](https://docs.slack.dev/admins/scim-api/) document the duplicate-email behavior.

## Reliability, rate limits, and failure handling

Membership synchronization should be a reconciliation job, not a one-shot callback:

- Store desired Slack entitlement from Active Builder state and the last observed Slack state.
- Serialize jobs per Builder, make add/remove idempotent, and re-read state after ambiguous failures. Treat `already_in_channel` as successful add and `not_in_channel` as successful removal.
- Do not mark workspace admission complete merely because an invite API returned success. A person can remain an invited member until first sign-in, and Slack invitations expire after 30 days. [Slack's invited-member guide](https://slack.com/help/articles/360024686174-Invited-members-in-Slack) and [invitation guide](https://slack.com/help/articles/201330256-invite-new-members-to-your-workspace) distinguish invited from active members.
- Retry HTTP 429 only after Slack's `Retry-After` interval. Standard Web API limits apply per method, workspace, and app. Tier 2 means at least 20 calls/minute; Tier 3 means at least 50 calls/minute. [Slack's Web API rate-limit guide](https://docs.slack.dev/apis/web-api/rate-limits/) documents the buckets and retry behavior.
- SCIM limits are shared by all SCIM apps in the organization: 600 writes/minute and 1,000 reads/minute overall, with per-user-endpoint limits of 180 creates, updates, or deletes/minute. SCIM also locks each user during a write; concurrent writes to the same user return 429 and must honor `Retry-After`. [SCIM rate limits](https://docs.slack.dev/reference/scim-api/rate-limits/) and [SCIM concurrency rules](https://docs.slack.dev/reference/scim-api/) document these constraints.

Expected operational failures include:

- **Plan/configuration:** `feature_not_enabled` for Admin APIs; `plus_teams_only` for SCIM; org token installed on a workspace instead of the org.
- **Authorization:** missing/revoked/expired token, missing scope, installer no longer an Admin/Owner, app not in the channel, workspace invitation/channel-management policies, or insufficient rights over a higher-role user.
- **Identity/state:** invalid or duplicate email, unknown/deactivated/removed user, already invited/present, pending invitation, user in the org but not the target workspace, or a Single-Channel Guest already assigned elsewhere.
- **Channel:** wrong/archived channel ID, private-channel visibility, `#general`, externally shared or multi-workspace channel restrictions.
- **Transient/ambiguous:** rate limiting, timeouts, service failures, or Slack's documented `fatal_error`/`internal_error` cases where some aspect may already have succeeded. Reconcile before retrying to avoid reversing or duplicating the desired transition.

At Rails Builders scale these quotas are unlikely to be a throughput problem. Permissions, identity drift, invite acceptance, and workspace topology are the real reliability risks.

## App review and distribution implications

For one Rails Builders workspace, use an internal app associated with that workspace. Slack says an undistributed app exists on a single workspace and may use the full range of app capabilities. That does not require Slack Marketplace review, though the workspace's own app-approval policy may require a Workspace Owner or app manager to approve the installation and scopes. [Slack's distribution guide](https://docs.slack.dev/app-management/distribution/) and [workspace app-approval guide](https://slack.com/help/articles/222386767-Manage-app-approval-for-your-workspace) distinguish those reviews.

Enterprise Admin API or SCIM installation is more involved. Slack requires OAuth and an org-wide installation, and its setup instructions require activating public distribution to complete the organization OAuth handshake. That switch does **not** make Marketplace listing appropriate: Slack says the Marketplace is not for an app built only for one's own team, and Marketplace submissions cannot request `admin.*` scopes. [Slack's SCIM installation guide](https://docs.slack.dev/admins/scim-api/) describes the org OAuth flow; the [Marketplace review guide](https://docs.slack.dev/slack-marketplace/slack-marketplace-review-guide/) excludes internal apps and `admin.*` scopes.

If this app later becomes a commercially distributed product for unrelated Slack workspaces, it needs a new distribution decision. Slack recommends Marketplace review for commercial distribution, while the broad Admin API scopes used for full workspace lifecycle are not Marketplace-eligible. That future product cannot simply reuse the internal provisioning design.

## Feasible v1 boundaries

### Boundary A — recommended if Builders already belong to the workspace

Automate only membership in one dedicated, non-`#general`, non-Slack-Connect channel:

- Internal Slack app with a bot token.
- Bot is a member of the target channel.
- `users:read.email` for initial identity discovery, plus `users:read` for deactivated-user reconciliation.
- Public channel: `channels:write.invites` and `channels:manage`.
- Private channel: `groups:write.invites` and `groups:write`.
- Persisted Slack team/user IDs, desired-state job, retries, reconciliation, audit log, and Administrator exception queue.
- Active Builder -> invite if absent. Inactive Builder -> kick if present.
- Explicitly no workspace invitation, role change, guest expiration, workspace removal, or account deactivation.

This boundary uses the narrowest available permissions and does not disturb a Builder's unrelated Slack access.

### Boundary B — feasible if Rails Builders owns a standalone Enterprise workspace

Automate workspace admission as a Single-Channel Guest with `admin.users.invite`, using the Rails Builders channel and optional guest expiration. On inactivity, use `admin.users.remove` rather than SCIM deactivation; use `admin.users.assign` for a known Enterprise user who must be reinstated. This requires a privately operated org-wide app, an enduring privileged user token, and Enterprise owner/admin cooperation.

### Boundary C — technically possible but poor fit on standalone Business+

SCIM can create and deactivate a full member of a standalone Business+ workspace. It cannot fully create a Single-Channel Guest, and deactivation revokes the whole workspace account. Use this only if the entire workspace is the Rails Builders entitlement and administrators accept the broad `admin` token. It is not a channel-membership solution.

### Boundary D — required when workspace admission is needed without those prerequisites

Expose a reliable Administrator queue instead of pretending automation succeeded: verified email, desired guest/member role, target channel, invite status, requested/fulfilled timestamps, retry/resend action, and inactive-removal task. Free/Pro workspaces and paid workspaces where Rails Builders does not control SCIM/Admin API credentials fall here.

## Actual workspace gate

The workspace-specific facts were inventoried on 2026-08-22 in [Rails Builders Slack Workspace Inventory](rails-builders-slack-workspace-inventory.md). The actual space is the standalone Free `Loop Labs 🧪` workspace (`T0AMMNQ9EMR`). Its dedicated target is now the private, local, non-Slack-Connect `#rails-builders` (`C0BRTLZRX51`). No Rails Builders membership app/token exists, the connected Slack read installation cannot access this workspace, and approved-domain self-join is enabled.

The settled ceiling is Pro and the intended role is Single-Channel Guest assigned only to `#rails-builders`. That choice selects Boundary D: an Owner/Admin must manually admit and deactivate guests, while the Rails app may expose an honest operational queue. Pro cannot automate the guest's workspace lifecycle, and channel-only automation is insufficient because removing an existing identity from the channel does not remove it from the workspace. Business+ full-member SCIM and Enterprise guest Admin APIs are documented expansion paths, not current recommendations or implementation authorization.

The channel-agent question is independent. Slack documents AI apps/agents as unavailable to guests, and Agentforce additionally requires Salesforce licensing and account mapping. A local Hermes integration as a normal bot is the smallest useful prototype, but its behavior from a disposable Single-Channel Guest account must be proven before it becomes a product promise.
