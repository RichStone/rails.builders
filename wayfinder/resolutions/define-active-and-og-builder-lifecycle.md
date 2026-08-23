# Resolution: Define the Active Builder and OG Builder Lifecycle

OG status records participation history and is independent of current enrollment. It does not end when a Builder becomes active or inactive. The end date of Continuous also does not change enrollment automatically.

An Active Builder begins when a current Seat Offer is accepted. Active status ends when the Builder turns off active membership, an Administrator removes the Builder, or the account is deleted. A voluntary exit releases the Seat, triggers the next offer, queues Slack offboarding, and allows later waitlist opt-in. Administrator removal also releases the Seat and queues Slack offboarding but blocks self-service re-entry until an Administrator reinstates the person.

The dashboard exposes separate membership and waitlist controls without creating a second source of truth. Turning off the waitlist clears the rank and makes the person inactive; turning it on joins the end of the queue and may immediately produce an offer when promotion is open and capacity is available. Seat Offers retain explicit accept and decline actions rather than behaving like a toggle.
