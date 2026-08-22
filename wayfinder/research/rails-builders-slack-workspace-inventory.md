# Rails Builders Slack Workspace Inventory

- Inventoried: 2026-08-22
- Decision updated: 2026-08-22 after the dedicated channel was created and the Pro/guest boundary was settled
- Evidence policy: actual Slack connector responses and signed-in Slack administration UI for workspace facts; first-party Slack documentation for API and plan boundaries
- Mutation policy: no Slack messages, membership changes, app installations, permission changes, or token creation were performed
- Gate question: Can the Rails app guarantee that every Active Builder belongs to the actual workspace and target channel, and that every non-active or deleted Builder belongs to neither?

## Gate result

**No. Do not implement Slack membership synchronization code.** The product decision is to remain on Free for now and consider Pro later, with each Builder admitted manually as a Single-Channel Guest whose only channel is the new private `#rails-builders`. Free has no guest roles. Pro supports the intended guest role, but has neither SCIM nor the Enterprise Admin Users API, so the Rails app cannot create, convert, assign, or deactivate those accounts through a supported API. [Slack guest-role guide](https://slack.com/help/articles/202518103-Understand-guest-roles-in-Slack), [Slack SCIM guide](https://docs.slack.dev/admins/scim-api/), [Slack Admin Users guide](https://docs.slack.dev/admins/managing-users/)

The dedicated channel fixes the former primary-channel problem, but channel-only automation remains insufficient. `conversations.invite` and `conversations.kick` operate on an existing workspace identity; they do not make that identity a Single-Channel Guest, deactivate it from the workspace, or prevent workspace access through another path. On Pro, an Owner or Admin must perform and verify both admission and offboarding.

Business+ was relevant only as the smallest standalone-workspace plan with SCIM. Its SCIM path provisions full members, not the intended Single-Channel Guests, and is outside the settled plan ceiling. Enterprise can automate Single-Channel Guest invitation/removal with Admin APIs, but is likewise outside scope. Neither is a recommendation for Rails Builders now.

No adapter, reconciliation job, schema, or UI was added.

## Directly observed actual state

| Area | Observation | Evidence surface |
| --- | --- | --- |
| Workspace | Name `Loop Labs 🧪`; team ID `T0AMMNQ9EMR`; URL `https://joinlooplabs.slack.com` | Signed-in Slack workspace and administration UI |
| Plan and topology | Free is marked `CURRENT PLAN`. The workspace has its own plan page, workspace administration, and no organization/Enterprise surface. This is a standalone workspace. | Slack plan and administration UI |
| People | One workspace member: Rich, Slack user ID `U0AMS32820N`, email `hey@richsteinmetz.com`, account type `Primary Workspace Owner`, active, default authentication, joined 2026-03-20 | Slack **Manage members** UI |
| Target channel | Private `#rails-builders`, channel ID `C0BRTLZRX51`, created by Rich on 2026-08-22, with one member | Slack channel and channel-details UI |
| Channel topology | Private, active, local to this workspace, and not Slack Connect. There is no Organizations tab or external-organization indicator. | Slack channel and channel-details UI |
| Intended role | On Pro, each Builder is a Single-Channel Guest assigned only to `#rails-builders`. Free cannot represent this role. | Product decision plus actual plan |
| Installer authority | Rich is the Primary Workspace Owner. App approval is disabled and apps need not come from Marketplace; members may install apps from any source. Rich is currently the only person who can exercise that policy. | Slack member and App Management Settings UI |
| Installed/developer apps | The installed-app list and Rich's Slack developer catalog each contain only `Otto Labot` (`A0BKKTFMSP5`), a modern, not-distributed app. The `#rails-builders` Agents & apps panel currently contains no agent or app. | Slack Installed Apps, developer-app, and channel-details UIs |
| Existing app permissions | Otto has `app_mentions:read`, `chat:write`, `files:write`, `im:write`, `assistant:write`, `commands`, `channels:history`, `channels:read`, `files:read`, `groups:history`, `groups:read`, `im:history`, `im:read`, `mpim:history`, `mpim:read`, `reactions:read`, and `users:read`. It lacks `admin`, `users:read.email`, and channel membership write scopes. | Slack Otto permissions UI |
| Token situation | Otto's installed OAuth credential necessarily exists somewhere, but its value/storage was deliberately not inspected and it is not configured in this repository. No Rails Builders membership token exists. | Slack developer-app UI and repository configuration |
| Connector access | The connected Slack read installation lists only ClickFunnels (`T02E9NBRY`). It cannot access Loop Labs. An unrelated archived `#rails-builders` in ClickFunnels (`C0BP30DPHBK`) is not this channel. | Connected Slack read tools |
| Repository configuration | `.env` and `.env.development` define no Slack app ID, team ID, channel ID, bot token, user token, or SCIM token. The repository contains no Slack adapter or job. `User#slack_status` is a manual status only. | Repository configuration and source search |
| Join policy | Approved-domain self-join is enabled for `richsteinmetz.com` and `looplabs.cc`. | Slack **Settings & Permissions** UI |

The old public primary channel `#safe-space` (`C0AMMNQHX5H`) is no longer the target. It remains relevant only as historical evidence explaining why the dedicated channel was required.

## Settled Pro operating boundary

1. Upgrade to Pro only when guest access is needed.
2. An Owner or Admin manually invites each eligible person as a Single-Channel Guest assigned only to `C0BRTLZRX51`.
3. The Rails app may expose an Administrator queue with verified email, desired state, requested time, observed/manual completion time, and overdue/error state. It must not report Slack access as synchronized merely because an admin task exists.
4. An Owner or Admin manually deactivates every non-active or deleted Builder, then records the observed result. Removing the person only from `#rails-builders` does not satisfy offboarding.
5. Disable approved-domain self-join before treating workspace access as an enforced entitlement, or explicitly accept that the Rails app cannot guarantee the invariant.
6. Persist enough audit data outside the deletable user row to retain the Slack user ID and a pending offboarding task after local account deletion.

Slack permits up to five free Single-Channel Guests per paid active member. With only Rich as a paid active member, Pro would cover five Builders, not the program's nine Seats. Nine simultaneous Builder guests require at least two paid active members, which provide an allowance of ten Single-Channel Guests, or a different paid-member arrangement. [Slack guest-role guide](https://slack.com/help/articles/202518103-Understand-guest-roles-in-Slack), [Slack fair-billing policy](https://slack.com/help/articles/218915077-Slacks-Fair-Billing-Policy)

## Why SCIM, Zapier, and Free do not change the boundary

SCIM is a standardized identity-provisioning API. Slack exposes it as a REST API over HTTP for creating, updating, and deactivating workspace accounts, but only on Business+ and Enterprise. It is not a bot or channel API. Slack also states that SCIM cannot fully provision a Single-Channel Guest: it must first create a full member, then an admin must restrict that account in Slack's UI. [Slack SCIM guide](https://docs.slack.dev/admins/scim-api/), [Slack SCIM reference](https://docs.slack.dev/reference/scim-api/)

Single-Channel and Multi-Channel Guest roles are paid-plan features. On Free, Slack can invite a person only as a full workspace member. If a paid workspace downgrades to Free, Slack deactivates existing guests unless they are reactivated as full members. A full member who happens to participate only in `#rails-builders` is not access-limited to that channel. [Slack guest-role guide](https://slack.com/help/articles/202518103-Understand-guest-roles-in-Slack), [Slack Free-plan limitations](https://slack.com/help/articles/27204752526611-Feature-limitations-on-the-free-version-of-Slack), [Slack workspace invitation guide](https://slack.com/help/articles/201330256-Invite-new-members-to-your-workspace)

Zapier's current Slack action is **Invite User to Channel**, explicitly defined as inviting an **existing** Slack user to an existing channel. It cannot create a workspace identity, assign the Single-Channel Guest role, or deactivate the account, and it cannot grant itself Slack capabilities that the connected plan/token lacks. Zapier can still automate the surrounding Administrator queue, reminders, and completion logging. [Zapier Slack integration](https://zapier.com/apps/slack/integrations)

Slack's supported API that directly invites a Single-Channel Guest is `admin.users.invite` with `is_ultra_restricted`; that method and the corresponding workspace-removal APIs are Enterprise-only. [Slack `admin.users.invite` reference](https://docs.slack.dev/reference/methods/admin.users.invite/), [Slack Admin Users guide](https://docs.slack.dev/admins/managing-users/)

Slack Connect is a different model: the person remains a member of another workspace while organizations share a channel. Ordinary Slack Connect channels require paid plans for each organization, and external participants do not become guests in the Loop Labs workspace. It therefore does not satisfy the settled Single-Channel Guest design or the original workspace-membership invariant. [Slack Connect guide](https://slack.com/help/articles/115004151203-Slack-Connect-guide--work-with-external-organizations), [Slack Connect channel guide](https://slack.com/help/articles/360035092414-Use-Slack-Connect-to-work-with-other-companies-in-channels-Use-Slack-Connect-to-work-with-other-companies-in-channels)

A local Hermes agent could drive the signed-in Slack admin UI as robotic process automation. That may reduce clicks, but it depends on an Owner's live session, UI selectors, authentication challenges, and Slack's current screen flow. Treat it as human-approved operational assistance, not as authoritative or unattended membership synchronization.

## Channel agent boundary

An agent is not a membership authority. A local Hermes agent connected as an ordinary Slack bot/app, or a Salesforce Agentforce agent, could potentially participate in `#rails-builders`; neither can make Pro guest admission/offboarding automatic.

Slack's current AI-agent documentation says guests cannot use AI apps or agents. Agentforce also requires an Agentforce license and Slack-to-Salesforce account mapping; people without Salesforce accounts need provisional Salesforce licenses. These constraints make Agentforce unproven for the intended Single-Channel Guest audience. [Slack AI-agent guide](https://slack.com/help/articles/33076000248851-Work-with-AI-agents-in-Slack), [Slack Agentforce setup guide](https://slack.com/help/articles/36218109305875-Set-up-and-manage-Agentforce-in-Slack)

Hermes should be evaluated separately in two modes:

- As a normal private Slack bot that reads and responds in the channel. Whether a Single-Channel Guest can mention or otherwise interact with that bot must be proven; do not assume the Slack AI-agent restriction does or does not cover this shape.
- As a Slack-native AI agent. Slack documents this as unavailable to guests, so it is not a viable program promise unless Slack's actual Pro behavior proves otherwise.

No agent was installed, added to the channel, messaged, or reconfigured during this inventory.

## Safe test-account path

After a Pro upgrade, use `hey+rails-builders-slack-smoke-20260822@richsteinmetz.com`. Do not use Rich's owner account or a real Builder.

1. Manually invite the alias as a Single-Channel Guest assigned only to `#rails-builders`.
2. Verify it can sign in, can see only that channel, and cannot discover or enter any other workspace channel.
3. Add only the selected test agent/app after reviewing its scopes. Do not grant membership-management authority.
4. From the guest account, test the exact supported interaction: ordinary bot mention/message for Hermes, or Agentforce access if still being considered. Record whether the guest can see, invoke, and receive a response.
5. Manually deactivate the guest and verify it is signed out and absent from the workspace and channel.
6. Reinvite/reactivate the same identity once to prove the manual runbook and retained Slack user binding.

This is a product/operations proof, not an API automation proof. It must not open the membership-synchronization implementation gate.

## Unverified and deliberately not changed

- Pro guest invitation, sole-channel visibility, deactivation, and reactivation have not been exercised against this workspace.
- The actual paid-member count after a future Pro upgrade is not settled; therefore the nine-guest allowance is not yet secured.
- Hermes' connection method, app identity, token storage, exact scopes, hosting, and Single-Channel Guest interaction behavior are unverified.
- Agentforce licensing, Salesforce org connection, provisional-user licensing, account mapping, and guest behavior are unverified.
- The repository's production hosting and secret store are not settled.
- No Slack membership, channel membership, app, permission, workspace setting, or message was changed during this inventory.
