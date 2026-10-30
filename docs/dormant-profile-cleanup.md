# Community totals and dormant-profile goodbye

`CommunityStatistic.current` stores the all-time totals independently of accounts. Six cohorts since 2025 and 35 cohort finishers are historical figures supplied by Rich. Update these two historical totals when another cohort finishes; they are not inferred from current membership.

The migration backfills confirmed accounts with `verified_at >= 2026-09-01 00:00:00 UTC`. First email confirmation then increments the registrant total in the same database transaction. Repeated sign-ins do not increment it; account deletion does not decrement it. A newly created account, including a returning builder who signs up again after deletion, counts when confirmed.

`User.dormant_without_public_profile` selects confirmed accounts in the homepage's Dormant statuses with no public-profile opt-in. Staff are excluded. Public profiles awaiting approval are preserved. This scope does not delete anything, and no recurring cleanup is installed.

After a qualifying account deletion commits, `UserMailer.profile_annihilated` queues one transactional goodbye, regardless of optional enrollment-notification preferences. Scalar recipient details let delivery work after the account is gone. User mail delivery suppresses job-argument logging to avoid copying those details into application logs. The existing account-deletion path removes associated private data and anonymizes retained attendance. A rolled-back deletion sends nothing.

## Approval before cleanup

Rich reviewed the rendered email and exact candidate list, then approved the 18-account batch on October 30, 2026, with revised email copy. Run that one-time cleanup after deploying the revised templates, verifying each successful send with its provider message ID. The private production snapshot, preview and delivery receipts live outside the public repository in `~/.local/share/rails-builders/dormant-cleanup-2026-10-30/`. Recheck each approved ID against the current scope immediately before using `delete_account!`; skip accounts whose eligibility changed. Do not recreate a candidate list and delete additional accounts under an old approval.

Development email preview: `/rails/mailers/user_mailer/profile_annihilated`.

## Illustration

Generated with the built-in imagegen tool. Final asset: `app/assets/images/loop-monster-goodbye.png`. Character reference: the existing `loop-monster-broken-rails.png`.

Prompt:

> Use case: illustration-story. Create a new transactional-email illustration using the attached image ONLY as the exact character design/style reference for the Rails.Builders Loop Monster. Keep the friendly yellow spotted monster, mismatched large expressive eyes, curled loop tail, one red ball-tipped antenna, bold dark outlines and glossy cartoon shading. New scene: Loop Monster SMILING warmly and WAVING goodbye with one hand, holding a visibly BROKEN ruby gemstone (two cracked red faceted pieces together) in the other hand. Monster sits on a small section of neglected railway tracks covered with clearly visible delicate spider webs stretched between the rails and wooden sleepers. Friendly funny goodbye, not sad or scary. Centered compact square composition, fully visible character and tracks. No text, letters, logos, watermark or additional characters. Genuine transparent background, retain transparency. This is a new illustration, not a layout mockup.
