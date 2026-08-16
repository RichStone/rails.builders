# Resolution: Research Slack Membership Automation

Resolved by [Slack Membership Automation Research](../research/slack-membership-automation.md).

Decision-relevant answer: v1 can reliably synchronize an already-known workspace user into and out of one dedicated non-`#general` channel with a scoped internal Slack app. Workspace invitations and removals are not plan-independent: they require Enterprise Admin APIs or Business+/Enterprise SCIM, and SCIM deactivation is whole-workspace/org rather than channel-only. Unless workspace plan/topology and privileged installation access prove the Enterprise standalone-workspace path, choose channel-only automation plus an Administrator workflow for workspace admission/offboarding.
