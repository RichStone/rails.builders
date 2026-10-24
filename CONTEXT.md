# Rails Builders

Rails Builders is a focused enrollment, roster, and public-presentation context for the Rails Builders Group. It is not a general-purpose community platform.

## Language

**Rails Builders Group**:
The facilitated program in which Ruby and Rails builders work on useful products together.
_Avoid_: Community software, social network

**OG Builder**:
A past Rails Builders participant identified by a pre-seeded email address. The initial seed addresses come from private environment configuration and are never committed to the repository.
_Avoid_: Applicant, anonymous user

**Registrant**:
A person who submits an email address and must verify it before receiving an enrollment outcome.
_Avoid_: Member, Rails Builder

**Seat**:
One of nine available participant places in Continuous. Confirmed Active Builders and pending Seat Offers consume capacity; the Facilitator does not.
_Avoid_: Waitlist position, account

**Seat Offer**:
A Seat reservation for a person awaiting Administrator or Facilitator confirmation. Staff can confirm the Builder from their private Builder management profile or explicitly release an old reservation to offer capacity to someone else. Waiting requests do not expire automatically. Builders cannot activate their own Seat.
_Avoid_: Seat, waitlist notification

**Readiness Check**:
The Program-owned checklist a verified person confirms once before the “Join Builders” control appears. After joining, the dashboard shows the waiting Loop Monster instead of asking for the same checklist again. Completing the checklist is an explicit readiness statement, not an automated audit of the person’s product, offer, AI use, Rails use, funnel, or checkout.
_Avoid_: Application review, eligibility test

**OG Priority**:
The initial admission phase in which available Seat Offers go only to verified OG Builders. An Administrator ends OG Priority by opening remaining capacity to the ordered waitlist.
_Avoid_: Permanent eligibility rule

**Active Builder**:
A Rails Builder whose Seat in Continuous has been confirmed by an Administrator or Facilitator. Active Builder status continues until the person withdraws, reaches the Program's consecutive absence limit, an Administrator removes them, or their account is deleted; the program finish date does not end it automatically.
_Avoid_: OG Builder, Registrant, Facilitator

**Inactive Builder**:
A verified person with no Seat Offer, Seat, or Waitlist Entry, including a new Registrant who has not completed the Readiness Check and explicitly joined the waitlist, or a Builder whose Seat was released at the consecutive absence limit. An Inactive Builder may opt into the waitlist.
_Avoid_: Non-active Builder, former member

**Removed Builder**:
A person an Administrator has made ineligible for a Seat and the waitlist. A Removed Builder cannot self-enroll again until an Administrator reinstates them.
_Avoid_: Kicked user, banned account

**Waitlist Entry**:
A verified Registrant who has neither a Seat nor a pending Seat Offer. Waitlist Entries are ordered by their earliest registration time, subject to Administrator reordering; an unverified registration does not hold capacity or appear on the active waitlist.
_Avoid_: Member, Seat

**Waitlist Opt-In**:
The explicit “Join Builders” action by which an Inactive Builder completes the Readiness Check and requests a place in the waitlist. The dashboard asks them to allow a few days at most for staff review, highlights the optional public profile step, and unlocks the next-session meeting link only after staff activation. The request emails staff a private Builder management link; the Builder receives their enrollment confirmation and Calendar invite after approval.
_Avoid_: Automatic re-enrollment

**Waitlist Opt-Out**:
The explicit action by which a Waitlist Entry leaves the queue without deleting their account. Opting out releases the person's rank and makes them an Inactive Builder.
_Avoid_: Account deletion, Seat withdrawal

**Continuous**:
The Rails Builders edition with a start line on 3 September and a finish line on 17 December 2026. Reaching the finish line does not by itself end Active Builder status.
_Avoid_: Membership status

**Public Builder Profile**:
A person's name, image, products, and testimonial. Every field remains private unless the person requests publication and a Facilitator approves it; later profile or Product changes require fresh approval.
_Avoid_: Account, waitlist profile

**Product**:
An app, business, or offer a Rails Builder is developing, identified by a name and an optional URL. A Product can exist before it has a public website, and a Public Builder Profile may contain multiple Products.
_Avoid_: Project, product link

**Focus Product**:
The one Product a Rails Builder identifies as their main focus right now. The public Builder card leads with the Focus Product and may expand to reveal the others.
_Avoid_: Primary account, only product

**Stage Problem**:
A Product’s current bottleneck: Offer, Product, Traffic, or Business Model. Offer covers who buys and the promised outcome; Product covers delivery, quality, and activation; Traffic covers reaching the right customers. Stalled growth can prompt a return to earlier stages or a business-model review.
_Avoid_: Builder rank, maturity score

**Stage Problem Analysis**:
A one- or two-sentence, revisable explanation of a Product’s current bottleneck and the evidence or uncertainty behind that assessment. It is private Program context shared by the Builder, Facilitators, Administrators, and Active Builders.
_Avoid_: Public product description, proven diagnosis

**Anonymous Builder Card**:
A public placeholder representing a homepage-listed Builder whose Public Builder Profile is private or awaiting approval, without revealing their identity or app. Each card has a stable, server-generated nerd alias and its own decorative visual treatment, and can become a Public Builder Profile when its Builder opts in.
_Avoid_: Fake profile, stock person

**Facilitator**:
An Administrator-designated user who appears publicly as leading the Rails Builders Group, operates sessions, reviews Public Builder Profiles, and may promote a verified eligible person directly to Active Builder. Rich Steinmetz is the initial Facilitator.
_Avoid_: Administrator

**Administrator**:
A User with the assignable role authorized to manage all app data and settings, including assigning Administrators and Facilitators. Rich Steinmetz is the only initial Administrator.
_Avoid_: Facilitator

**Slack Entitlement**:
Access to the Rails Builders Slack workspace and dedicated channel owed to an Active Builder and enforced through the Administrator workflow supported by the current Slack plan. Public profile visibility and OG status do not affect Slack Entitlement.
_Avoid_: Slack status, profile publication
