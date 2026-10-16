# Strike-limit release email

The Program's configured limit automatically moves an Active Builder to Inactive, releases the Seat, sends this notice according to enrollment notification preferences, and removes upcoming Calendar invitations when the Program connection is available. A new activation resets the streak. See `StrikeLimitJob` and its job tests for the executable behavior.

Preview: `/rails/mailers/user_mailer/strike_limit_reached` in development. HTML and plain text live in `app/views/user_mailer/strike_limit_reached.*.erb`. The illustration is an inline MIME attachment at the top of the email, so it does not require a remote image request.

## Illustration

Generated with the built-in imagegen tool, using the existing Loop Monster at `LoopLabs/looplabs.cc/funnel/site/assets/loop-monster-ruby-rails.png` as the character reference. The final asset is `app/assets/images/loop-monster-broken-rails.png`.

Prompt:

> Use case: illustration-story. Asset type: warm, funny header illustration for a Rails.Builders membership pause email. Use the attached artwork as the character and visual-style reference. Preserve the Loop Monster's yellow spotted body, one very large eye and one smaller eye, red ball-tipped antenna, curled loop tail, little limbs, black cartoon outlines and glossy cheerful brand style. New scene: this same Loop Monster is sitting slumped on a short section of visibly broken railway rails with a small gap and bent broken ends. It is looking sadly and wistfully at a beautiful faceted red ruby resting nearby on a wooden sleeper. Its mouth is a small sad curve; mood tender, affectionate, gently comic, never angry or scary. Both the monster's seated pose and the broken rails must be unmistakable. Keep the ruby clearly visible and the character recognizable. Compose as a compact isolated illustration with generous transparent margin suitable at the top of a friendly email. No words, letters, captions, logos or watermark. Transparent background.

Calendar behavior follows Google's [recurring event guide](https://developers.google.com/workspace/calendar/api/guides/recurringevents) and [event patch API](https://developers.google.com/workspace/calendar/api/v3/reference/events/patch): update each recurring master once, include separately edited future exceptions, preserve other attendees and their responses, and guard each patch with its current ETag.
