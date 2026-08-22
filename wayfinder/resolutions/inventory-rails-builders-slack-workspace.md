# Resolution: Inventory the Rails Builders Slack Workspace

Resolved by the [actual workspace inventory](../research/rails-builders-slack-workspace-inventory.md).

The real Rails Builders Slack is the standalone Free `Loop Labs 🧪` workspace (`T0AMMNQ9EMR`). Its Builder-facing `#safe-space` channel (`C0AMMNQHX5H`) is public, local, and the renamed primary channel. Rich (`U0AMS32820N`) is its sole member and Primary Workspace Owner. No Rails Builders membership app or token exists; the only installed app is Otto Labot, whose scopes cannot provision or remove workspace members. Approved-domain self-join is enabled for `richsteinmetz.com` and `looplabs.cc`.

End-to-end automation is therefore blocked and unauthorized. Channel-only automation is insufficient: it cannot admit or deactivate workspace accounts, and Slack cannot kick anyone from this primary channel. The smallest supported route is Business+, owner-authorized SCIM with full-member accounts, approved-domain self-join disabled, durable Slack identity bindings, and a successful disposable-account lifecycle proof. Until all of those prerequisites are met, Slack membership remains an Administrator workflow.
