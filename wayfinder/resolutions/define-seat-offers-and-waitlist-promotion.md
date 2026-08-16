# Resolution: Define Seat Offers and Waitlist Promotion

Continuous begins with nine configurable Seats. The Facilitator does not consume one. A confirmed Active Builder and a pending Seat Offer each consume one unit of capacity, so the invariant is `active + pending <= capacity`.

Only a verified email can enter enrollment. During OG Priority, a verified OG Builder receives a Seat Offer immediately when capacity is available; every other verified Registrant becomes a Waitlist Entry even when capacity remains. An Administrator ends OG Priority by opening remaining capacity to the waitlist. From then on, whenever capacity is available, the app automatically issues offers from the top of the Administrator-ordered waitlist until capacity is reserved. Reordering affects only future offers and never revokes a pending offer or confirmed Seat. Administrators may pause and resume promotion.

A Seat Offer expires 72 hours after issue and sends the recipient an offer, a reminder with 24 hours remaining, and a confirmation or expiry outcome; Rich receives corresponding status notifications. Confirmation is an explicit, idempotent action and does not require profile completion or public visibility. Declining or expiring an offer does not automatically recreate a Waitlist Entry. Withdrawing from a confirmed Seat likewise releases capacity without re-enrollment. Each of those people may explicitly opt in again, which places a fresh entry at the end of the waitlist.

Increasing capacity triggers promotion when OG Priority has ended and promotion is not paused. Decreasing capacity never revokes an existing Seat or pending offer; it pauses new promotion until occupancy is below the new limit.

Enrollment transitions and capacity selection must be serialized transactionally so concurrent verification, confirmation, expiry, withdrawal, reordering, and capacity edits cannot exceed capacity or offer the same queue position twice. Repeated verification and confirmation requests are idempotent. Email delivery is a retryable side effect: a transition remains authoritative, delivery failures appear to Administrators, and no email failure rolls back enrollment state. Administrators may retry notifications or cancel an undeliverable pending offer to release its capacity.

Live-session controls, attendance, timers, and Three Strikes are outside this ticket and outside v1.
