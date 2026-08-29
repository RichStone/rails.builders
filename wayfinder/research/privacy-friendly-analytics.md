# Analytics options for Rails Builders

- Researched: 2026-08-29
- Scope: page views, selected clicks, and conversion measurement across the public homepage, email sign-in flow, and signed-in Rails application
- Decision lenses: capability-first follow-up plus the original privacy-first comparison
- Evidence: first-party product documentation, source repositories, and regulator guidance only
- This is product and technical research, not legal advice.

## Capability-first recommendation

Choose **PostHog Cloud** if Rails Builders should have one analytics product across both the public website and the signed-in application. It combines a ready-made web traffic dashboard with product funnels, retention, paths, autocapture, session replay, heatmaps, feature flags, experiments, surveys, and error tracking. The free tier currently includes one million analytics events, 5,000 session recordings, one project, unlimited team members, and one year of data retention. Usage stops at the free limit unless billing is enabled ([web analytics](https://posthog.com/web-analytics), [pricing](https://posthog.com/pricing)).

Choose **Google Analytics 4** instead when the main question is acquisition: which search query, referral, campaign, or ad produced registrations? GA4 is free, any event can become a key event, Funnel Exploration supports ordered open or closed funnels, and the integrations with Google Ads and Search Console are its decisive advantage. Standard properties can also export raw event data to BigQuery ([GA4 overview](https://marketingplatform.google.com/about/analytics/), [key events](https://support.google.com/analytics/answer/9267568), [funnels](https://support.google.com/analytics/answer/9327974), [Search Console](https://support.google.com/analytics/answer/10737381), [BigQuery export](https://support.google.com/analytics/answer/9823238)).

GA4 can track the signed-in application, but it is a marketing analytics product first. It has no native heatmaps, session replay, surveys, feature flags, or experimentation, and behavioral product questions generally take more report configuration than PostHog. The standard tier also limits event-level exploration data retention to 14 months and may sample explorations above 10 million events per query, although Rails Builders is unlikely to approach that volume ([data retention](https://support.google.com/analytics/answer/7667196), [property limits](https://support.google.com/analytics/answer/12229528)).

For maximum capability while both free tiers fit, **GA4 plus PostHog** is the strongest combination: Google supplies acquisition attribution while PostHog supplies the product analysis and qualitative tooling. It also duplicates page views, conversion events, identities, and dashboards, and the products will not produce identical user or session totals. Do not start with both unless acquisition and product analytics are already equally important.

The cheaper qualitative companion to GA4 is **Microsoft Clarity**: GA4 handles traffic sources, key events, funnels, and attribution; Clarity adds unlimited-traffic heatmaps, session recordings, and frustration signals. Clarity is explicitly free forever and integrates with GA4 ([Clarity](https://clarity.microsoft.com/), [GA integration](https://clarity.microsoft.com/blog/give-google-analytics-a-boost-with-clarity/)). The cost is still two client tags, two datasets, and more configuration. It is not the lightweight default.

### Capability-first shortlist

| Product | Best at | Current free entry point | Main tradeoff for Rails Builders |
|---|---|---:|---|
| **PostHog** | Best one-tool website + product stack | 1M events, 5K recordings, one project, one-year retention | Broader and heavier than a simple counter; acquisition integrations trail Google |
| **GA4** | Acquisition, channel attribution, SEO, and Google Ads | Free standard property | Less pleasant for product analysis; no replay, heatmaps, flags, or experiments |
| **Mixpanel** | Polished funnels, retention, flows, and cohorts | 1M events, 10K replays, 10 flags, experiments for 1K monthly evaluated users | Free plan allows only five saved reports per seat; replay retention is 30 days ([pricing](https://mixpanel.com/pricing/)) |
| **Amplitude** | Broad enterprise-style analytics and experimentation | 2M events, session replay, flags, experiments, surveys, unlimited seats | More platform than this project needs; free plan has ten saved charts per organization and one year of data access ([pricing](https://amplitude.com/pricing)) |
| **Heap** | Retrospective autocapture with minimal up-front event design | 10K monthly sessions, core charts, six months of history | Autocapture creates a noisier data model; less compelling than PostHog once explicit conversion events are required ([pricing](https://www.heap.io/pricing)) |
| **Clarity** | Free visual diagnosis | Unlimited-traffic recordings and heatmaps | A companion to an analytics system, not the primary source for product funnels and attribution |

Mixpanel and Amplitude are excellent products, but neither has a decisive advantage for this small Rails application. PostHog offers the clearest path from the initial measurement needs into replay, experiments, feature flags, surveys, and engineering diagnostics without adding another vendor. Heap is most attractive when retroactive no-code discovery is the overriding requirement, which is not the case here because registration and enrollment conversions must still be emitted after successful Rails state changes.

### Capability-first implementation choice

Do not install multiple full analytics suites initially. Pick the question that matters most:

- Choose **PostHog** for “Where do visitors or members get stuck, and which product behaviors predict registration or enrollment?”
- Choose **GA4** for “Which acquisition channel or campaign produces verified registrations and enrolled members?”
- Choose **GA4 + PostHog** only when both acquisition and product analytics are immediately important enough to justify duplicate tracking.
- Choose **GA4 + Clarity** when acquisition plus free visual replay is sufficient.

For the stated scope across homepage, sign-in, and app pages, **PostHog is the overall recommendation**. If Rails Builders begins buying Google Ads or prioritizes SEO acquisition, prefer GA4 or add it later on public pages only.

Removing privacy from the ranking does not remove applicable legal or security obligations. In every product, retain the allowlisted event and normalized-route design below, and never send verification tokens, newsletter tokens, email addresses, private page titles, or record IDs.

## Privacy-first recommendation

Start with **Umami Cloud Hobby**, provided the account can be contractually or operationally pinned to its EU service region. It is the best match for the complete requirement: a sub-2 KB, cookieless tracker; automatic page views; explicit click/form events; and ordered funnels built from page views and events. The hosted Hobby plan is free for low-traffic sites, while the self-hosted software is open source ([Umami introduction](https://docs.umami.is/docs), [cloud FAQ](https://docs.umami.is/docs/cloud/faq), [events](https://docs.umami.is/docs/track-events), [funnels](https://docs.umami.is/docs/funnel)).

Do **not** self-host Umami on the Rails Builders server initially. This application deliberately has no Node runtime and uses SQLite, while Umami requires a Node service plus PostgreSQL. Adding both to the one production host would expand deployments, patching, monitoring, capacity planning, and backups merely to avoid a small hosted dependency ([Umami installation requirements](https://docs.umami.is/docs/install)). Revisit self-hosting only if vendor residency cannot be made explicit or the cloud plan stops fitting.

Umami is privacy-oriented, but its product language should not be mistaken for anonymous aggregate counting. It derives a session identifier from the visitor's IP address, user agent, and site identifier; the default self-hosted salt rotation is monthly. It says the raw IP is used for location and never stored. This is much less invasive than advertising analytics, but the session-level journey is still the feature that makes funnels possible and deserves transparent disclosure and a documented legal basis ([Umami sessions](https://docs.umami.is/docs/sessions), [metric definitions](https://docs.umami.is/docs/metric-definitions), [salt rotation setting](https://docs.umami.is/docs/environment-variables)). Never call `umami.identify`, never send a Rails user ID or email, and do not enable replay or heatmaps.

Umami's public cloud FAQ says its servers are in both the US and EU and that the service adheres to GDPR, but it does not state on that page which region a particular Hobby project uses. Confirm the EU selection and applicable DPA before sending production data. If that cannot be confirmed, use the fallback below rather than assuming EU residency ([Umami Cloud FAQ](https://docs.umami.is/docs/cloud/faq), [Umami DPA](https://umami.is/umami-dpa.pdf)).

## Privacy-first fallback

Use hosted **GoatCounter** when strict data minimization matters more than a built-in ordered funnel. It is donation-supported and free for reasonable public usage, adds about 3.5 KB, supports page views and explicitly tagged click events, stores aggregate tables by default, uses no cookie/local storage identifier, and hosts the service on Hetzner in Finland and Germany ([GoatCounter overview and pricing](https://www.goatcounter.com/), [event tracking](https://www.goatcounter.com/help/events), [data handling](https://www.goatcounter.com/help/privacy)).

GoatCounter can receive success counters from the Rails backend, so a real `email_verified`, `waitlist_joined`, or `seat_confirmed` outcome can be recorded rather than treating a button click as a conversion ([backend API](https://www.goatcounter.com/help/backend)). Its aggregate-first design cannot reliably answer “how many of the same visitors completed this ordered sequence?” Conversion rates would instead be ratios such as successful verifications divided by sign-in page visits. That is probably enough for the present community-sized application, but it is not a true funnel.

Before choosing hosted GoatCounter, verify that its contractual terms meet the controller's Article 28 needs. Its public privacy page is unusually clear about the data path, but the researched pages do not advertise an automatically executed DPA.

## Best inexpensive paid alternatives

| Product | Current entry point | Why choose it | Important limit |
|---|---:|---|---|
| **Pirsch Standard / Plus** | $6 / $12 monthly at 10,000 page views | Germany-hosted, cookieless, DPA, browser or server-side collection, custom events and conversion goals on Standard; actual multi-step funnels on Plus | Uses an IP/user-agent-derived visitor hash; not free after the 30-day trial ([pricing](https://pirsch.io/pricing), [events](https://docs.pirsch.io/advanced/events)) |
| **Plausible Business** | Starts at $19/month for 10,000 monthly page views on the displayed annual pricing | Strongest documented hosted privacy posture: no cookies or persistent identifiers, EU-owned infrastructure, EU-only visitor data, and an automatic DPA; supports custom events and funnels | No free hosted plan; funnels are Business-only, and free Plausible CE deliberately omits them ([compliance](https://plausible.io/compliance), [plans](https://plausible.io/docs/subscription-plans), [funnels](https://plausible.io/docs/funnel-analysis), [CE comparison](https://plausible.io/self-hosted-web-analytics)) |

Pirsch is the practical paid upgrade for this project. Plausible is the premium choice when documented EU-only processing and procurement simplicity outweigh price.

## Options not recommended now

| Product | Why not for Rails Builders now |
|---|---|
| **Cloudflare Web Analytics** | Free and privacy-oriented, but it still has no custom events or UTM support, so it cannot satisfy click and conversion tracking ([Cloudflare FAQ](https://developers.cloudflare.com/web-analytics/faq/)). |
| **Simple Analytics Free** | Fine for a traffic pulse, but the free plan has only 30 days of history and excludes goals/events; it does not meet the complete requirement ([pricing](https://www.simpleanalytics.com/pricing)). |
| **PostHog Cloud EU** | Very generous free tier and excellent product analytics, but it is a much larger behavioral analytics system than this application needs. Its own guidance puts responsibility for consent and collection configuration on the customer. The free tier includes one million events, but the added identity, autocapture, replay, and configuration surface are a privacy and maintenance mismatch ([pricing](https://posthog.com/pricing), [privacy controls](https://posthog.com/docs/privacy)). |
| **Ahoy for Rails** | Free, first-party, and Rails-native, with cookie-free/IP-masked settings and server-side events. However, it adds visit/event data to the application database, has no complete analytics dashboard by itself, and creates retention/deletion/reporting work. It is useful when full first-party ownership is mandatory, not as the lowest-effort starting point ([Ahoy](https://github.com/ankane/ahoy)). |
| **Matomo** | Capable and configurable, but operationally much heavier than Umami or GoatCounter for this small, single-server app. The regulator guidance specifically treats consent exemption as configuration- and purpose-dependent, not a product-name guarantee ([CNIL audience measurement guidance](https://www.cnil.fr/fr/node/677)). |

## Measurement plan

Do not “track every click.” Use a small allowlist tied to actual decisions.

### Acquisition funnel

1. `home_view` — public `/`
2. `join_cta_clicked` — attach a `placement` value from the fixed allowlist `header`, `hero`, `format`, `readiness`, or `footer`
3. `sign_in_view` — public `/sign-in`
4. `registration_created` — emit only after a new user record saves; the same form also signs in existing users
5. `registration_verified` — emit only on the first transition from unverified to verified

Measure returning authentication separately with `verification_link_requested` and `sign_in_completed`; otherwise repeat sign-ins will be misreported as new registrations.

### Enrollment funnel

1. `dashboard_view` — normalized route name only
2. `waitlist_joined` — successful server-side state transition
3. `seat_offer_presented` — server-side or normalized dashboard state, without a user identifier
4. `seat_confirmed` — successful server-side state transition

### App engagement

Use only normalized page/event names such as `dashboard`, `sessions_index`, `session_join_clicked`, `profile_edit`, and `profile_publication_requested`. Do not send record IDs, raw dynamic URLs, page titles, query strings, verification/newsletter tokens, names, emails, attendance data, session/transcript text, or product URLs. Exclude administration and facilitator surfaces unless a later decision identifies a concrete operational question they must answer.

For Turbo navigation, verify one and only one page-view event per completed visit. Record conversions only after the successful server-side state transition, not on submit-button clicks; otherwise validation errors and expired tokens inflate the numbers. For an Umami funnel, the server can render a one-time, allowlisted success marker on the redirected page and let the browser tracker emit the anonymous event. A backend event is fine for an exact aggregate counter but must not be assumed to join the originating browser session automatically.

The automatic tracker must not be dropped indiscriminately into the shared layout. This application puts verification and newsletter tokens in query parameters, and Umami normally extracts and stores query parameters. At minimum, set `data-exclude-search="true"`; better, exclude `/verify` and `/newsletter/confirm` from client analytics entirely and emit only their successful server-side outcome events. On signed-in pages, disable automatic page views and send an allowlisted, normalized route label so dynamic record IDs and private page titles never leave the application ([Umami tracker configuration](https://docs.umami.is/docs/tracker-configuration), [metric definitions](https://docs.umami.is/docs/metric-definitions)).

## Privacy and launch gates

The current privacy notice says, “The site does not add advertising cookies or analytics trackers.” That becomes factually wrong as soon as any client analytics script is deployed. Before enabling analytics:

1. update the notice with the analytics purpose, provider, fields/categories, legal basis, recipients, residency/transfers, retention, and objection or consent mechanism as applicable;
2. execute or verify the provider DPA and EU region;
3. document a legitimate-interest assessment if that is the chosen GDPR basis;
4. keep collection aggregate and anonymous/pseudonymous, with no account linking;
5. establish a short retention period and deletion/export procedure;
6. honor an accessible opt-out even if no cookie banner is required; and
7. test the exact network payloads on public, sign-in, verification, dashboard, and session pages before production.

Cookieless analytics does not automatically remove every privacy obligation. CNIL's regulator guidance says audience-measurement consent exemptions are conditional: users must be informed and able to object, measurement must be limited to the publisher's own audience/A-B testing, data must not be cross-matched, scope must remain within one publisher, IP data must be truncated, and tracer lifetime must be limited. National implementation can vary ([CNIL audience measurement guidance](https://www.cnil.fr/fr/node/677)).

## Privacy-first bottom line

- Choose **Umami Cloud Hobby** for the requested page views + clicks + real funnel reporting, after confirming the EU region/DPA.
- Choose **GoatCounter** if “free and maximally minimal” beats ordered funnel attribution.
- Choose **Pirsch Plus** if spending $12/month is acceptable and a German-hosted, supported funnel product is preferable.
- Choose **Plausible Business** when the cleanest documented EU vendor/privacy story is worth the higher price.
