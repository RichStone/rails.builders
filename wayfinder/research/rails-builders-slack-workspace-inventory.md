# Rails Builders Slack Workspace Inventory

- Inventoried: 2026-08-22
- Evidence policy: actual Slack connector responses and signed-in Slack administration UI for workspace facts; first-party Slack documentation for API and plan boundaries
- Mutation policy: no Slack messages, membership changes, app installations, permission changes, or token creation were performed
- Gate question: Can the Rails app currently guarantee that every Active Builder belongs to the actual workspace and target channel, and that every non-active or deleted Builder belongs to neither?

## Gate result

**No. Do not implement Slack synchronization code under the current configuration.** The actual workspace is a standalone Free workspace. Slack provides no workspace-provisioning API on that plan, no Rails Builders app or token is installed or configured, and the target conversation is the renamed primary channel, from which `conversations.kick` cannot remove a person. Channel-only automation cannot admit a Builder to the workspace, cannot remove their workspace account, and cannot satisfy the product invariant.

The smallest supported route to full automation is to upgrade this standalone workspace to Business+, keep Builders as full members, authorize a privately operated SCIM integration, disable approved-domain self-join, and prove the lifecycle with a disposable account. Slack limits SCIM to Business+ and Enterprise and requires an OAuth user token with the broad `admin` scope; on Business+, an Owner or Admin can generate that token and must retain the role. [Slack SCIM guide](https://docs.slack.dev/admins/scim-api/)

That route is a prerequisite, not an implementation authorization. No adapter, reconciliation job, schema, or UI was added.

## Directly observed actual state

| Area | Observation | Evidence surface |
| --- | --- | --- |
| Workspace | Name `Loop Labs 🧪`; team ID `T0AMMNQ9EMR`; URL `https://joinlooplabs.slack.com` | Signed-in Slack workspace and administration UI |
| Plan and topology | Free is marked `CURRENT PLAN`. The workspace has its own plan page, workspace administration, and no organization/Enterprise surface. This is a standalone workspace, not an Enterprise workspace inside an organization. | Slack plan and administration UI |
| People | One workspace member: Rich, Slack user ID `U0AMS32820N`, email `hey@richsteinmetz.com`, account type `Primary Workspace Owner`, active, default authentication, joined 2026-03-20 | Slack **Manage members** UI |
| Target channel | `#safe-space`, channel ID `C0AMMNQHX5H`, one member, created by Rich on 2026-03-20. It was renamed from `#all-funnels-on-rails` on 2026-07-25. | Slack channel and channel-details UI |
| Channel topology | Public, active, local to this workspace, and not Slack Connect. It has no lock, external-organization indicator, or Organizations tab, and its only member is the sole local workspace member. | Slack channel and channel-details UI |
| Primary-channel status | Slack's Default Channels setting says new members are added to configured defaults "in addition to `#safe-space`." Therefore `#safe-space` is the renamed primary (`#general`) channel, not an ordinary removable channel. | Slack **Settings & Permissions** UI |
| Intended role | Full member. Free has no guest role, and this workspace is itself the Rails Builders access boundary. | Actual plan/topology plus the product invariant |
| Installer authority | Rich is the Primary Workspace Owner. App approval is disabled and apps need not come from Marketplace; members may install apps from any source. Rich is currently the only person who can exercise that policy. | Slack member and App Management Settings UI |
| Installed/developer apps | The installed-app list and Rich's Slack developer catalog each contain only `Otto Labot` (`A0BKKTFMSP5`), a modern, not-distributed app. No Rails Builders membership app is installed or configured. | Slack Installed Apps and developer-app UIs |
| Existing app permissions | Otto has `app_mentions:read`, `chat:write`, `files:write`, `im:write`, `assistant:write`, `commands`, `channels:history`, `channels:read`, `files:read`, `groups:history`, `groups:read`, `im:history`, `im:read`, `mpim:history`, `mpim:read`, `reactions:read`, and `users:read`. It lacks `admin`, `users:read.email`, and channel membership write scopes. | Slack Otto permissions UI |
| Token situation | The developer catalog lists no app-configuration token and offers `Generate Token`. Otto's installed OAuth credential necessarily exists somewhere, but its value/storage was deliberately not inspected and it is not configured in this repository. No Rails Builders OAuth or SCIM token exists. | Slack developer-app UI and repository configuration |
| Connector access | The connected Slack read installation lists only ClickFunnels (`T02E9NBRY`). It does not have access to Loop Labs. A connector search found an unrelated archived, empty `#rails-builders` test channel in ClickFunnels (`C0BP30DPHBK`); that is not the actual Rails Builders workspace/channel. | Connected Slack read tools |
| Repository configuration | `.env` and `.env.development` define no Slack app ID, team ID, channel ID, bot token, user token, or SCIM token. The repository contains no Slack adapter or job. `User#slack_status` is a manual status only. | Repository configuration and source search |
| Join policy | Approved-domain self-join is enabled for `richsteinmetz.com` and `looplabs.cc`. A person controlling an address on either domain can join independently of Rails Builders desired state. | Slack **Settings & Permissions** UI |

## Current blockers

1. **Plan:** Free cannot use SCIM, and Slack's Admin Users API is Enterprise-only. Manual workspace invitations/deactivations are possible, but the Rails app cannot enforce them. Slack documents SCIM as Business+/Enterprise only. [Slack SCIM guide](https://docs.slack.dev/admins/scim-api/)
2. **Primary channel:** `#safe-space` is the renamed primary channel. Slack returns `cant_kick_from_general` when `conversations.kick` targets that channel. [Slack method reference](https://docs.slack.dev/reference/methods/conversations.kick/)
3. **Credentials and scopes:** no Rails Builders Slack app/token exists in the workspace or repository. Otto is a different app and lacks the required scopes.
4. **Enforcement bypass:** approved-domain self-join can recreate workspace access outside the Rails app. It must be disabled for a strict desired-state invariant.
5. **Identity binding:** the Rails app has verified, normalized email, but the actual Slack workspace has no Builder accounts to match. The schema stores only a manually selected `slack_status`; it does not persist `team_id`, Slack user ID, provisioning state, or a tombstone that survives local user deletion.
6. **Deletion ordering:** a Rails Builder can be hard-deleted. Full automation needs a durable binding/outbox so Slack deactivation is not lost when the local `users` row disappears.

**Channel-only automation is insufficient.** It cannot cross the workspace boundary, and it cannot remove anyone from this particular primary channel. On this dedicated workspace, workspace deactivation is the operation that removes a person from both the workspace and all channels.

## Smallest required change

The minimum plan/authority/configuration package is indivisible:

1. Upgrade `T0AMMNQ9EMR` from Free to Business+.
2. Retain Rich as a durable Primary Workspace Owner and have him authorize a private internal app/user token with the SCIM `admin` scope. Slack requires the token-generating account to remain an Owner/Admin. [Slack SCIM guide](https://docs.slack.dev/admins/scim-api/)
3. Use full-member provisioning. Business+ SCIM cannot provision guest accounts; Slack limits SCIM Multi-Channel Guest provisioning to Enterprise and cannot fully provision Single-Channel Guests through SCIM. [Slack SCIM guide](https://docs.slack.dev/admins/scim-api/), [SCIM reference](https://docs.slack.dev/reference/scim-api/)
4. Disable approved-domain self-join for `richsteinmetz.com` and `looplabs.cc`, or explicitly weaken the product invariant. A strict gate cannot coexist with an unmanaged re-entry path.
5. Store the SCIM token outside the repository, configure the fixed team/channel IDs, and persist Slack's user ID as the durable identity after initial verified-email resolution.
6. Complete the disposable-account test below before authorizing production code.

Pro is not sufficient: it still has neither SCIM nor the Enterprise Admin Users API. Enterprise is not the smallest change because the actual workspace is standalone and its entire membership is the entitlement being managed.

## Conditional API path after prerequisites are met

This is the exact path to prove before the implementation gate may open. Use SCIM v2 at `https://api.slack.com/scim/v2` with a bearer user token carrying `admin`.

### Active Builder admission

1. Require a verified Rails Builders email and `enrollment_status == "active"`.
2. Reconcile with paginated `GET /Users?count=1000&startIndex=1` and match the normalized verified email against every returned `emails[].value`, including inactive users. Never create a second identity for a previously deactivated email; Slack rejects duplicate-email provisioning even when the old account is inactive. [Slack SCIM guide](https://docs.slack.dev/admins/scim-api/)
3. If absent, call `POST /Users` with the SCIM core schema, `userName`, primary `emails`, name/display name when available, and `active: true`. Slack documents `userName` plus at least one email as required and returns the Slack user resource. [SCIM reference](https://docs.slack.dev/reference/scim-api/)
4. If present but inactive, reactivate that exact Slack ID with `PATCH /Users/{slack_user_id}` setting `active` to `true`.
5. Persist `(team_id: "T0AMMNQ9EMR", user_id)` and the normalized source email in a binding that survives deletion of the local user.
6. Do not call `conversations.invite` for `C0AMMNQHX5H`: as the primary channel, Slack adds every workspace member automatically. Re-read SCIM state and channel membership before reporting `active` to the Administrator.

### Non-active or deleted Builder removal

1. Resolve the durable stored Slack user ID; never select a removal target from a mutable email alone.
2. Refuse to target `U0AMS32820N` or any Workspace Owner/Admin unless an explicit, separately authorized administrative workflow has first changed the Slack role.
3. Call `DELETE /Users/{slack_user_id}`. Slack defines this as setting the Slack user to deactivated. [SCIM reference](https://docs.slack.dev/reference/scim-api/)
4. Do not call `conversations.kick` for `C0AMMNQHX5H`; the method cannot remove a member from the primary channel. Deactivation removes the person from every channel, signs them out, and prevents sign-in, which satisfies both workspace and channel removal in this standalone workspace. [Slack deactivation guide](https://slack.com/help/articles/204475027-Deactivate-a-members-account)
5. Re-read the SCIM resource and observed channel/workspace state before reporting `removed`. Retain the binding so later reactivation uses the same Slack identity.

### Required public seams if implementation is later authorized

- An adapter contract for lookup/provision/reactivate/deactivate/observe that returns explicit desired and observed states without exposing tokens.
- A serialized reconciliation job driven by Active Builder desired state, including local deletion tombstones, idempotency, `Retry-After`, and re-read-after-ambiguous-failure behavior.
- Administrator-visible desired state, observed workspace/channel state, Slack user ID, last attempt/success, pending invitation or activation, error, retry action, and an immutable exclusion for the Primary Workspace Owner.

## Safe disposable-account proof

Use `hey+rails-builders-slack-smoke-20260822@richsteinmetz.com`, which is already controlled by Rich and has been used as a Rails Builders application smoke identity. Do not use Rich's owner account or a real Builder.

After the Business+ upgrade, app authorization, and approved-domain self-join removal:

1. Create and verify the matching local Rails Builders account without making it an Administrator, Facilitator, or OG Builder.
2. Transition it to Active Builder and run one reconciliation.
3. Confirm SCIM returns a new or reactivated full member with a stable Slack ID and confirm automatic membership in `#safe-space`.
4. Complete Slack sign-in through the alias inbox to prove the invited/pre-provisioned account is usable.
5. Transition it to a non-active status, reconcile, and prove the SCIM resource is inactive, the account is signed out, and it is absent from all channels.
6. Repeat active → inactive once to prove reactivation, idempotency, and reuse of the same Slack ID.
7. Delete the local smoke account and prove the durable tombstone still deactivates Slack before marking the test complete.

Do not run this proof against the current Free plan: it would exercise only manual membership and could not prove the production API invariant.

## Unverified and deliberately not changed

- No SCIM or membership token exists yet, so token generation, token rotation, and real SCIM calls remain unverified.
- No non-owner workspace account exists, so email-match, invite acceptance, reactivation, deactivation, and channel-removal behavior remain unproven against this workspace.
- The repository's production hosting and secret store are not settled, so outbound IP allowlisting and durable token ownership remain unverified.
- No Slack membership, channel, app, permission, workspace setting, or message was changed during this inventory.
