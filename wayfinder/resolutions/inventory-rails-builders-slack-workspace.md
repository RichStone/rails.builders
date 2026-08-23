# Resolution: Inventory the Rails Builders Slack Workspace

Resolved by the [actual workspace inventory](../research/rails-builders-slack-workspace-inventory.md).

The real Rails Builders Slack is a standalone Free workspace. The dedicated Builder-facing `#rails-builders` channel is private, local, not Slack Connect, and currently contains only the workspace's Primary Workspace Owner. No agent or app is in the channel. No Rails Builders membership app or token exists; the one unrelated installed app cannot provision or remove workspace members. Approved-domain self-join is enabled. Exact workspace, channel, app, and personal identifiers are deliberately omitted from public source.

The settled ceiling is Pro, with Builders manually managed as Single-Channel Guests assigned only to `#rails-builders`. End-to-end membership automation is therefore blocked and unauthorized: Pro has no supported API for creating, assigning, or deactivating those guest accounts, and channel-only automation cannot satisfy workspace offboarding. The Rails product may track an Administrator queue but must not claim synchronization. With one paid active member, Pro includes only five free Single-Channel Guests; the nine-Seat program needs at least two paid active members or a different paid-member arrangement.

Hermes or Salesforce Agentforce is a separate channel-agent decision, not a membership mechanism. Slack documents AI apps/agents as unavailable to guests, while Agentforce additionally needs Salesforce licensing and account mapping. A disposable Single-Channel Guest must prove the exact interaction before either agent becomes a program promise; a normal Hermes bot is the least-assumptive first test.
