# ClickFunnels Integration for the Loop Labs Newsletter

- Researched: 2026-08-09
- Scope: subscribe a newsletter-confirmed, email-verified Rails Builders Registrant in the existing Loop Labs ClickFunnels workspace
- Evidence: first-party ClickFunnels documentation, the published OpenAPI schema, and authenticated read-only API inspection of the Loop Labs workspace

## Decision-relevant answer

Use a server-side reconciliation job that:

1. upserts the ClickFunnels contact by the Registrant's canonical verified email;
2. reads the returned contact's tags and email-suppression state;
3. if the contact is active and does not already have it, applies the existing `newsletter-subscriber` tag; and
4. records the returned ClickFunnels contact id and sync outcome locally.

For Loop Labs, the resolved production identifiers are:

| Resource | Identifier |
|---|---|
| Workspace | raw id `477369`, public id `vNAEpW`, subdomain `humanontheloop` |
| Newsletter tag | raw id `448334`, public id `jYqAlB`, name `newsletter-subscriber` |
| Rails Builders provenance tag | raw id `448335`, public id `JNbnob`, name `Rails.Builders` |
| Email topic | raw id `488873`, public id `eWgLoE`, name `General` |

These are verified by authenticated reads of the first-party [Loop Labs tags API](https://humanontheloop.myclickfunnels.com/api/v2/workspaces/477369/contacts/tags), [workflows API](https://humanontheloop.myclickfunnels.com/api/v2/workspaces/477369/workflows), and [email-topics API](https://humanontheloop.myclickfunnels.com/api/v2/workspaces/477369/emails/topics). The endpoints require authentication; the findings above contain no contact data or credentials.

The `newsletter-subscriber` tag is the only currently configured, API-writable newsletter-audience marker. The separate `Rails.Builders` tag is useful provenance, but it is not required to represent newsletter membership.

There is **no documented public endpoint for enrolling one contact into an Emails::Topic**. The published schema contains topic CRUD only (`/workspaces/{workspace_id}/emails/topics` and `/emails/topics/{id}`), and no contact-topic subscription resource ([published OpenAPI schema](https://developers.myclickfunnels.com/openapi/clickfunnels-api.json); [Email APIs GA changelog](https://developers.myclickfunnels.com/changelog/email-apis-are-now-generally-available)). Therefore the v1 integration should not invent a “list” or topic-enrollment call. Newsletter broadcasts must use the `General` topic required by ClickFunnels and target the `newsletter-subscriber` tag through a contact filter. The undocumented question of how an API-created contact becomes subscribed to `General` must be verified with a controlled delivery test before the first production broadcast.

## Verified API facts

### Authentication and host

- Create an API access token under a ClickFunnels platform application. API tokens are generated per team and can access the team's workspaces. Team admins can see them, so the Rails app must hold the token only as a server-side secret ([Getting Started](https://developers.myclickfunnels.com/docs/getting-started)).
- Send `Authorization: Bearer <token>` and a distinct `User-Agent`; ClickFunnels says the user agent is required by its security rules ([Authentication](https://developers.myclickfunnels.com/docs/authentication)).
- Use HTTPS and JSON with `Content-Type: application/json` ([Requests and Responses](https://developers.myclickfunnels.com/docs/requests-and-responses)).
- Workspace-specific calls should use the workspace's own subdomain. For this integration the base is `https://humanontheloop.myclickfunnels.com/api/v2` and the raw workspace id is `477369` ([Getting Started](https://developers.myclickfunnels.com/docs/getting-started)).
- An own-team API key is sufficient. OAuth and trusted cross-team platform access are unnecessary for a Rails Builders service writing to Rich's own Loop Labs workspace; ClickFunnels reserves the trusted-platform gate for a third-party OAuth platform writing across teams ([first-party Workflows skill, Authentication](https://accounts.myclickfunnels.com/.well-known/workflows/skill.md#authentication)).

### Contact upsert and tags

- `POST /workspaces/{workspace_id}/contacts/upsert` matches on email. It returns `201` when it creates the contact and `200` when it updates an existing match ([Upsert a Contact](https://developers.myclickfunnels.com/reference/upsertcontacts)). This is the correct duplicate-contact seam; do not implement “GET then create” with the ordinary Create Contact endpoint.
- Upsert does not clear existing values when passed empty values. Its shared contact parameter schema also warns that a supplied `tag_ids` array can overwrite existing tags. The safe integration therefore omits `tag_ids` from upsert and manages the newsletter tag separately ([Upsert a Contact](https://developers.myclickfunnels.com/reference/upsertcontacts)).
- The returned contact includes `id`, `public_id`, `tags`, `is_active`, `unsubscribed_at`, and `email_suppression_reason`. Applying a tag is `POST /contacts/{contact_id}/applied_tags` with `{"contacts_applied_tag":{"tag_id":448334}}`, returning `201` ([Create Applied Tag](https://developers.myclickfunnels.com/reference/createcontactsappliedtags)).
- Contact-tag names are unique within a workspace; trying to create a duplicate name returns validation errors. The existing tag should be resolved/validated, not re-created per subscription ([tag uniqueness changelog](https://developers.myclickfunnels.com/changelog/tag-names-now-require-uniqueness-per-workspace); [List Tags](https://developers.myclickfunnels.com/reference/listcontactstags)).
- The reference documents no `Idempotency-Key` header and does not document what a duplicate Applied Tag POST returns. Application-level reconciliation must not depend on undocumented duplicate behavior ([published OpenAPI schema](https://developers.myclickfunnels.com/openapi/clickfunnels-api.json)).
- ClickFunnels exposes global email suppression on contacts and exposes a bulk unsubscribe action, but the public contact write schema has no resubscribe field or resubscribe action ([Contacts API changelog](https://developers.myclickfunnels.com/changelog/add-email-engagement-data-and-filtering-to-contacts-api); [published OpenAPI schema](https://developers.myclickfunnels.com/openapi/clickfunnels-api.json)). Applying a tag must never be treated as overriding `is_active: false`, `unsubscribed_at`, or `email_suppression_reason`.

### Lists, topics, and workflows are different resources

- “List Contacts” is a query endpoint, not a newsletter-list membership resource. Contacts can be segmented with tags and Refine filters ([List Contacts](https://developers.myclickfunnels.com/reference/listcontacts)).
- Emails::Topic endpoints manage topic definitions for subscriber preferences. They do not expose contact enrollment in the published API ([Create Email Topic](https://developers.myclickfunnels.com/reference/createemailstopic); [published OpenAPI schema](https://developers.myclickfunnels.com/openapi/clickfunnels-api.json)).
- ClickFunnels now supports manual workflow enrollment with `POST /workflows/{workflow_id}/runs`; the workflow must be live and the contact must be in the same workspace ([Enroll Contact](https://developers.myclickfunnels.com/reference/createworkflowrun)).
- Authenticated read-only inspection found one relevant live workflow, `Loop Labs Welcome: Optin` (`pzxMxD`). Its trigger is the page-scoped `$optin` event and its only step sends an email; it does not apply `newsletter-subscriber`. Upserting a contact is not documented as emitting a page opt-in event. Therefore this workflow is neither the membership write nor something the Rails app should assume will run automatically ([workflow triggers API](https://humanontheloop.myclickfunnels.com/api/v2/workflows/pzxMxD/triggers); [workflow steps API](https://humanontheloop.myclickfunnels.com/api/v2/workflows/pzxMxD/steps); [first-party Workflows skill](https://accounts.myclickfunnels.com/.well-known/workflows/skill.md)).

## Exact request sequence

The job should run only after the Rails app has both a verified registration email and the newsletter-specific confirmation required by [the consent research](newsletter-consent.md).

### 1. Upsert the contact

```http
POST https://humanontheloop.myclickfunnels.com/api/v2/workspaces/477369/contacts/upsert
Authorization: Bearer <CLICKFUNNELS_API_TOKEN>
User-Agent: RailsBuilders/1.0 (https://rails.builders)
Content-Type: application/json

{
  "contact": {
    "email_address": "<canonical verified email>",
    "first_name": "<first name, when collected>",
    "last_name": "<last name, when collected>"
  }
}
```

Accept `200` and `201`. Persist the returned `public_id` and raw `id`. Do not send `tag_ids`.

If `is_active` is false, `unsubscribed_at` is set, or `email_suppression_reason` is set, stop before claiming success. Retain the Registrant's local consent evidence, record a `blocked_suppressed` sync state, and show an Administrator action. The public API does not provide a verified way to reactivate that address.

### 2. Reconcile the existing newsletter tag

If the returned `tags` already contains raw id `448334` or public id `jYqAlB`, this step is complete. Otherwise:

```http
POST https://humanontheloop.myclickfunnels.com/api/v2/contacts/<contact-public-id>/applied_tags
Authorization: Bearer <CLICKFUNNELS_API_TOKEN>
User-Agent: RailsBuilders/1.0 (https://rails.builders)
Content-Type: application/json

{
  "contacts_applied_tag": {
    "tag_id": 448334
  }
}
```

Accept `201`. A retry always restarts from contact upsert and re-checks the returned tags before attempting this POST. Thus a lost `201` response is safe: the next upsert observes the already-applied tag and finishes without posting it again.

If Rails Builders provenance is required, reconcile tag `448335` with the same pattern as a separate concern. It should not be coupled to whether the person consented to the newsletter.

### 3. Do not enroll a workflow by default

The current `Loop Labs Welcome: Optin` workflow is an email side effect, not newsletter membership. If the later flow decision explicitly chooses to send that existing welcome email, manually enroll only after the tag is reconciled:

```http
POST https://humanontheloop.myclickfunnels.com/api/v2/workflows/pzxMxD/runs
Authorization: Bearer <CLICKFUNNELS_API_TOKEN>
User-Agent: RailsBuilders/1.0 (https://rails.builders)
Content-Type: application/json

{
  "run": {
    "contact_id": "<contact-public-id>",
    "skip_communication": false
  }
}
```

Manual run creation is not documented as idempotent. Before retrying an ambiguous response, list runs filtered by the contact and treat a matching active, paused, or completed manual run as success. Also protect the operation with a unique local welcome-delivery record. Do not use `force_run` or the bulk run-workflow action for a single Registrant.

## Idempotency and concurrency design

These are application design recommendations derived from the verified API behavior:

1. Give each local sync one unique key, for example `(registrant_id, "loop_labs_newsletter")`, and serialize it with a database row lock or an equivalent single-flight job guard.
2. Treat Rails Builders' canonical verified email as immutable input to this sync. Changing an account email should be a separate reconciliation flow; silently upserting the new address could create a second ClickFunnels contact.
3. Make the job a reconciler, not a sequence of “create” commands: upsert, inspect, apply only missing state, verify, persist.
4. Mark the local sync successful only after the contact is active and the response shows the newsletter tag, or after the tag POST succeeds and a follow-up read confirms it.
5. Never delete contacts, clear tags, or reset existing contact fields from the subscription job.

This prevents duplicate local jobs and makes an unknown network outcome recoverable without relying on an undocumented ClickFunnels idempotency header. The email-keyed upsert prevents a normal retry from creating a second contact. It cannot safely merge any historical duplicate contacts that already exist; surface multiple matches to an Administrator rather than guessing which record to delete.

## Rate limits, failures, and retries

ClickFunnels documents dynamic rate limiting with a “generous quota” but publishes no numeric limit and says the mechanism may change ([Rate Limiting](https://developers.myclickfunnels.com/docs/rate-limiting)). Its response guide defines `429` for rate limits, `4xx` client errors, and `5xx` server errors ([Requests and Responses](https://developers.myclickfunnels.com/docs/requests-and-responses)).

Recommended handling:

| Outcome | Handling |
|---|---|
| `200`, `201` | Success; persist returned ids/state. |
| Network timeout, connection failure, `429`, `500`-`599` | Retry the whole reconciler with exponential backoff and full jitter. Honor `Retry-After` if ClickFunnels supplies it, but do not assume that header is present. |
| `400`, `422` | Permanent payload/business validation failure. Store the sanitized response and show Administrator action; do not loop. |
| `401`, `403` | Token/permission configuration failure. Stop retries and alert immediately. |
| `404` | Stale workspace, contact, tag, or workflow configuration. Re-resolve once; if still missing, fail permanently and alert. |
| `409` | Re-fetch and reconcile once; if the conflict remains, require Administrator action. |

Use a small bounded worker pool; this flow is far below bulk-import scale and should not depend on discovering a fixed quota. A practical retry schedule is seconds, then minutes, then hours, capped at about 24 hours. After the cap, retain `failed` state plus a manual retry control. The Registrant's Rails Builders account must not be rolled back because ClickFunnels is unavailable; newsletter sync is an observable, retryable side effect.

## Unresolved boundary and required smoke test

The public API cannot explicitly enroll a contact into `General`, and first-party documentation does not state whether a contact created with the upsert endpoint is automatically subscribed to that system topic. Before enabling the first production newsletter broadcast:

1. create a consenting test contact through the exact reconciler;
2. confirm it has `newsletter-subscriber` and remains `is_active: true`;
3. create a test broadcast on `General` filtered to that tag and a single controlled address;
4. verify delivery and one-click unsubscribe; and
5. verify the unsubscribe changes ClickFunnels suppression so later filtered sends exclude it.

If that test shows topic membership is missing, the current public API is insufficient for fully automated subscription. Escalate to ClickFunnels API support rather than adding an undocumented private endpoint or browser automation.

## Sources

- [ClickFunnels Getting Started](https://developers.myclickfunnels.com/docs/getting-started)
- [Authentication](https://developers.myclickfunnels.com/docs/authentication)
- [Requests and Responses](https://developers.myclickfunnels.com/docs/requests-and-responses)
- [Rate Limiting](https://developers.myclickfunnels.com/docs/rate-limiting)
- [Upsert a Contact](https://developers.myclickfunnels.com/reference/upsertcontacts)
- [Create Applied Tag](https://developers.myclickfunnels.com/reference/createcontactsappliedtags)
- [List Contact Tags](https://developers.myclickfunnels.com/reference/listcontactstags)
- [Enroll Contact (Create Workflow Run)](https://developers.myclickfunnels.com/reference/createworkflowrun)
- [Create Email Topic](https://developers.myclickfunnels.com/reference/createemailstopic)
- [Published ClickFunnels OpenAPI schema](https://developers.myclickfunnels.com/openapi/clickfunnels-api.json)
- [First-party ClickFunnels Workflows skill](https://accounts.myclickfunnels.com/.well-known/workflows/skill.md)

