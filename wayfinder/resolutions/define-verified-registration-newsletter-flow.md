# Resolution: Define the Verified Registration and Newsletter Flow

Passwordless Rails email verification and Loop Labs newsletter consent remain separate. A registrant may use Rails Builders without requesting the newsletter. Newsletter synchronization requires both a verified Rails email and the newsletter-specific confirmation; a Rails verification alone does not authorize newsletter transfer or tagging.

Production stores the ClickFunnels API token in the encrypted Rails credential `clickfunnels.api_token`. Development and test make no network request. Once both confirmations exist, an idempotent background job upserts the normalized email, preserves suppression, and reconciles the existing `newsletter-subscriber` tag. Administrators can see blocked or failed state and retry it. A controlled production smoke test proves delivery and unsubscribe behavior before launch.
