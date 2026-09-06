# Security and Authorization Design

This conceptual design applies the invariants in [PRODUCT_SPEC.md](PRODUCT_SPEC.md), [BUSINESS_RULES.md](BUSINESS_RULES.md), [ARCHITECTURE.md](ARCHITECTURE.md), and [DATABASE.md](DATABASE.md). It defines the required authorization boundary before policies or migrations are written; it does not contain deployable SQL.

## 1. Security Principles

- Deny access by default and grant only the minimum read or action required.
- Treat Flutter, cached data, route guards, and all request fields as untrusted. UI hiding is not authorization.
- Use Supabase Auth for identity, PostgreSQL RLS for row visibility, and controlled PostgreSQL functions for sensitive mutations.
- Derive authoritative timestamps, deadlines, completion validity, penalties, debt, and ranking facts on the server.
- Keep participation and administration independent and authorize every operation within one explicit challenge.
- Never ship the Supabase service-role key or other privileged secret in Flutter.
- Make financial history append-only and important business actions attributable and auditable.
- Fail closed when identity, challenge scope, role, target ownership, or required configuration cannot be proven.

## 2. Identity Model

```text
Supabase Auth user -> profiles -> challenge_members
                         |
                         +-----> challenge_admins (independent grant)
```

`auth.users.id` is the immutable login identity and equals `profiles.id`. A `challenge_members` row grants participation and eligibility only. A separate active `challenge_admins` row grants the full MVP challenge-admin role. A user may be participant-only, admin-only where the product permits, or both; membership never implies administration.

The MVP is private: no public challenge registration or open joining. A trusted provisioning flow creates access and a temporary credential. The user must replace it after first login and may later change their own password. An authorized admin may initiate a reset but cannot read an existing password. Passwords remain in Supabase Auth and never enter application tables, logs, audit snapshots, or notifications.

## 3. Data Classification

| Class | Examples | Default exposure |
|---|---|---|
| Private to user | Credential-state profile fields, notification preferences, device installations | Owner or trusted server only |
| Challenge-shared | Allowed display profile, habits/rules, roster, ranking, team activity | Active authorized challenge users |
| Participant + admin | Task/progress history, debt, payment requests, excuse requests | Record owner and active challenge admins only as needed |
| Admin-only | Management configuration, review queues, scoped audit detail | Active admins of that challenge |
| Server-only/highly sensitive | Raw device tokens, outbox internals, worker locks, privileged secrets | Trusted database/worker boundary only |

Views and RPC result types should expose only needed columns. Classification of a result does not authorize its mutation.

## 4. RLS Access Matrix

Legend: **Own** is a row belonging to `auth.uid()`; **Shared** is intentionally visible within an authorized challenge; **Admin** requires an active admin grant in that challenge; **RPC** means no direct client write; **Worker** means no `authenticated`/`anon` access. All application tables have RLS enabled, and omitted access is denied.

| Table | Participant SELECT | Admin SELECT | INSERT | UPDATE | DELETE |
|---|---|---|---|---|---|
| `profiles` | Own full safe profile; Shared display fields through a narrow view | Challenge-related display/credential-state fields only | Provisioning RPC | Own safe fields/password-state RPC | Forbidden |
| `challenges` | Shared for active/permitted membership | Admin challenge | Creation RPC | Admin RPC | Forbidden; end logically |
| `challenge_timezone_versions` | Shared history needed to explain tasks | Admin challenge | Admin RPC | RPC only to close unused/current range | Forbidden |
| `challenge_members` | Own plus permitted roster fields | Admin challenge | Admin provisioning/membership RPC | Admin membership RPC | Forbidden; change status |
| `challenge_admins` | Shared minimal active-admin identity if needed | Admin challenge grants | Admin authorization RPC | Revocation RPC | Forbidden |
| `challenge_pauses` | Shared | Admin challenge | Admin pause RPC | Admin resume RPC | Forbidden |
| `habits` | Shared | Admin challenge | Admin RPC | Admin RPC for safe current metadata | Forbidden after use |
| `habit_rule_versions` | Shared applicable/history | Admin challenge | Admin versioning RPC | RPC only to close an eligible range | Forbidden |
| `task_instances` | Own; team statistics only through safe views | Admin challenge | Worker/catch-up only | Completion/correction/closure RPC only | Forbidden |
| `task_progress_events` | Own | Admin challenge | Participant progress RPC | Forbidden | Forbidden |
| `task_corrections` | Own task corrections | Admin challenge | Admin correction/review RPC | Forbidden | Forbidden |
| `excuse_requests` | Own | Admin challenge review queue | Participant submit RPC | Independent-review RPC | Forbidden |
| `excuse_request_habits` | Own parent request | Admin challenge | Submit RPC | Review RPC sets decision fields once | Forbidden |
| `task_excuse_effects` | Own tasks | Admin challenge | Review/materializer RPC | Forbidden | Forbidden |
| `ledger_entries` | Own challenge ledger | Admin challenge finance | Domain RPC/worker only | Forbidden | Forbidden |
| `payment_requests` | Own | Admin challenge review queue | Participant submit RPC | Independent-review RPC | Forbidden |
| `activity_events` | Shared safe feed | Shared/admin challenge | Domain RPC/worker only | Forbidden | Forbidden |
| `notification_preferences` | Own | No routine access; narrow support view only | Own tightly constrained upsert | Own delivery-mode fields only | Forbidden; reset by update |
| `notifications` | Own | No blanket access; only separately authorized support/audit data | Domain RPC/worker only | Own `read_at` only | Forbidden |
| `device_tokens` | No raw-token SELECT; own installation metadata via RPC/view | None | Registration RPC | Rotation/disable RPC | Forbidden; disable logically |
| `notification_outbox` | None | None | Worker/domain function only | Dispatcher only | Worker retention policy only, never client |
| `audit_log` | No base-table access; narrow own history views if required | Admin challenge, redacted/scoped | Domain RPC/worker only | Forbidden | Forbidden |

RLS must evaluate effective membership/admin state, not a client role claim. Column grants or restricted views must prevent a permissive row policy from exposing protected columns.

## 5. RPC Authorization

Every public function derives the actor from `auth.uid()`, resolves challenge and target rows from server data, rechecks authorization after locks, uses one transaction, and records a stable `request_id` where retries are possible.

| Operation | Caller and required checks | Time, self-review, transaction, and idempotency |
|---|---|---|
| `complete_task` | Authenticated active participant; task belongs to caller and challenge membership | Capture server time; task open/eligible and `<= deadline_at`; lock task; idempotent completion/activity |
| `record_task_progress` | Authenticated active participant; own task; amount/type valid | Server-derived acceptance/local date; active window; lock and append event; request-key and occurrence uniqueness |
| `submit_excuse_request` | Authenticated active participant; own challenge membership and nonempty challenge habit set | Server `submitted_at`; atomic parent/children/notice; idempotent request |
| `review_excuse_request` | Active admin in request challenge; actor must differ from participant | Lock pending request; server review time; approved subset only; atomic effects/corrections/waivers/audit; one terminal decision |
| `submit_payment_request` | Authenticated active participant; own challenge debt; amount/currency valid | Recalculate debt; one pending per member/challenge; server time; atomic request/notice; idempotent |
| `approve_payment_request` | Active admin in request challenge; actor must differ from participant | Lock request/finance scope; revalidate pending and debt; atomically append one payment ledger entry, decision, audit, notice |
| `reject_payment_request` | Active admin in request challenge; actor must differ from participant | Lock pending request; server review time; no ledger effect; terminal compare-and-set and idempotency |
| `admin_correct_task` | Active admin in task challenge; resolve target member and classify transition server-side | Beneficial self-correction forbidden; trusted evidence required for on-time; lock; append correction/audit and update projection atomically |
| `waive_penalty` | Active admin in ledger challenge; actor must differ from beneficiary | Lock source/finance scope; cap remaining relief; append linked entry and audit; unique request/source; no timing change |
| `change_membership_status` | Active admin in membership challenge | Validate effective transition with server time; atomically neutralize affected open tasks, audit, and notify; idempotent |
| `create_or_version_habit_rule` | Active admin in habit challenge | Server validates effective range, schedule, target, finance, reminders; insert version/audit atomically; non-overlap and request uniqueness |
| `change_challenge_timezone` | Active admin in challenge | Future/unopened periods only; server effective time; version/audit transaction; range/request uniqueness |
| `pause_challenge` | Active admin in challenge | Server start time; lock lifecycle; neutralize open tasks and audit atomically; compare-and-set/idempotent |
| `resume_challenge` | Active admin in challenge | Server end time; lock active pause/lifecycle; audit atomically; compare-and-set/idempotent |
| `materialize_open_tasks` | Trusted scheduler only; authenticated users may at most call a narrow self-scoped catch-up wrapper | Server time/config; bounded transaction; unique task-period identity makes retries converge |
| `close_due_tasks` | Trusted scheduled worker only | Server time; locked batches; atomic outcome/penalty/events/outbox; unique sources and retry-safe claims |
| `dispatch_notification_outbox` | Trusted dispatcher only | Claim locked due jobs; no domain decisions; per-device uniqueness, bounded retries, safe terminal error state |

No sole-admin bypass exists. Their own excuse/payment remains pending, and their self-benefiting waiver or correction is rejected until a different active admin acts.

## 6. `SECURITY DEFINER` Functions

Use `SECURITY DEFINER` only when a domain transition must bypass direct RLS to update protected rows atomically. Prefer invoker-security functions for ordinary reads.

Each definer function must have a non-login owner, a fixed safe `search_path`, and schema-qualified object references. Revoke default `PUBLIC` execution and grant only the intended role: selected participant RPCs to `authenticated`, admin RPCs to `authenticated` with an internal active-admin check, and workers only to a trusted execution role. Never grant worker functions to client roles.

The function must validate `auth.uid()`, reject a missing identity, derive the actor rather than accept `user_id`, resolve challenge scope from locked targets, and enforce ownership/admin/self-review rules inside the function. Avoid caller-controlled dynamic SQL and unsafe calls to mutable helper functions. RLS bypass makes a missing check catastrophic, so keep functions small, reviewable, transaction-safe, and covered by negative tests.

## 7. Client-Supplied Identifiers

Client identifiers select a candidate record; they never prove ownership or authority. Participant RPCs accept `task_id`, request content, and an idempotency key, then bind the actor through `auth.uid()`. An interface such as `complete_task(task_id, arbitrary_user_id)` is prohibited.

Admin commands may name a target member, request, habit, or ledger row, but the server resolves its challenge and verifies the caller's active grant in that same challenge. Ignore or reject client `is_admin`, `role`, debt, status, currency, completion time, beneficiary, and challenge fields that can be derived from the target. Opaque UUIDs reduce accidental disclosure but are not authorization.

## 8. Time Security

Capture one database-generated authoritative instant at the start of each decision and use it consistently through that transaction. Device time and client timezone are presentation inputs only. The server owns the effective-dated IANA challenge timezone and converts local schedules into frozen UTC `opens_at` and `deadline_at` values.

Participants cannot backdate. Completion accepted at exactly `deadline_at` is on time; later receipt is rejected even if a queued client action claims an earlier time. Historical corrections never manufacture an authoritative timestamp. `COMPLETED_ON_TIME` requires a pre-existing trusted server record proving the target was reached by the deadline; otherwise acknowledgment is `COMPLETED_LATE` with no artificial ranking timestamp.

## 9. Financial Security

`ledger_entries` is the immutable, challenge-scoped source of truth and debt is derived from signed entries. Participants cannot directly insert, update, or delete ledger rows. A payment submission creates only a pending request and does not reduce debt.

Independent approval locks the payment and finance scope, confirms the reviewer is a different active admin, recalculates current debt and currency, and atomically appends exactly one `PAYMENT_CONFIRMED` entry. The database enforces at most one pending request per participant/challenge and unique financial source/request identifiers. Rejection has no ledger effect.

Waivers and negative adjustments require a different active admin from the beneficiary, cannot over-credit the source/debt, and append a linked compensating entry. No correction deletes or rewrites a financial fact. Challenge currency must match throughout and becomes immutable after the first ledger entry.

## 10. Excuse Security

A participant may submit only their own excuse, within one challenge, with a nonempty habit set and valid reason/range. They cannot review it or mutate its requested scope after submission. An active challenge admin may approve, reject, or narrow the scope, but must differ from the participant; this is checked server-side after resolving the request owner.

Review records the actor, authoritative time, requested and approved scope, reason/context, effects, and audit event in one transaction. Approved habit reductions become immutable participant-visible effects. A late approval preserves the original missed/penalty facts and, when relief is justified, appends an independently authorized waiver rather than deleting the penalty.

## 11. Historical Correction Security

Only an active challenge admin may correct history. The server resolves the task participant, computes whether the transition benefits completion, accountability, or ranking, and prohibits a participating admin from beneficially correcting their own task. A different active admin is required.

Every correction has a mandatory reason, actor, server `recorded_at`, immutable old/new state, and audit linkage. On-time classification requires a referenced, pre-existing trusted server event whose authoritative timestamp proves completion by the deadline. User testimony, a manual time, editable metadata, device clock, or screenshot is insufficient. A separate penalty waiver changes finance only and never changes completion timing or ranking evidence.

## 12. Notification Security

Raw FCM tokens are highly sensitive. Users manage only their own installation through a controlled registration/rotation/disable API; they cannot read another token, and ordinary admins never read tokens. Store protected token material, use a non-reversible hash for uniqueness, and redact tokens from logs and audit.

The outbox is server/dispatcher-only. Users read only their own private notifications and may change only `read_at`; team activity is a separate intentionally challenge-visible stream. Push payloads contain no secrets, tokens, excuse reasons, detailed debt, or sensitive audit data. Because lock screens may be observed, prefer generic text such as “A payment request was updated” and reveal details only after authenticated in-app access.

## 13. Realtime Security

Realtime publication must preserve the same RLS and column exposure as normal reads. Suitable streams are safe `activity_events`, a user's own task/status changes, own notification rows, and own payment/excuse status—or admin review queues within the authorized challenge. Publish only required columns or security-safe views.

Do not broadly publish ledger details, free-form excuse reasons, audit snapshots, device tokens, outbox rows, or internal idempotency data. A subscription to another challenge ID must return no rows. The team feed contains only deliberately shared event metadata; Realtime is neither push delivery nor an authority for state transitions.

## 14. Admin Data Visibility

An active admin may see challenge-scoped monitoring, habits/rules, membership, participant task history, penalties/debt, payment and excuse review data, and redacted audit history needed for management. Authorization is evaluated per challenge and may use focused views for queues and dashboards.

Admin status does not justify unrestricted table access. Admins do not receive plaintext passwords, Auth secrets, service credentials, raw device tokens, outbox internals, unrelated challenges, or private notification inboxes. Free-form reasons and profile fields should be exposed only when necessary for the specific review/support workflow.

## 15. Audit Security

`audit_log` is append-only and writable only as a side effect of trusted functions/workers. Each entry identifies challenge, actor (or named system operation), action, target, authoritative time, request/correlation ID, reason when required, and minimized old/new state. It never replaces the domain event itself.

Active challenge admins may read redacted audit rows for their challenge. Participants do not query the base log; narrow views may expose correction/decision history affecting their own records. Audit JSON must exclude passwords, reset material, tokens, service secrets, unnecessary excuse text, and oversized payloads. Updates/deletes are denied to clients and ordinary admins; retention, export, and operator access require a separate controlled policy.

## 16. Service Role and Server Secrets

Flutter may contain the normal public Supabase URL/client key intended for RLS-protected client use. It must never contain the Supabase service-role key, Firebase server credentials, private signing keys, database administrator credentials, or temporary participant passwords beyond the immediate login interaction.

Privileged secrets live only in approved Edge Function, scheduler, deployment, or CI secret storage. Deployments fail closed when required secrets are missing—there are no development fallback credentials in production. Restrict access, rotate on suspected exposure, separate environments, and prevent secrets from entering source control, build logs, crash reports, analytics, or push payloads.

## 17. Edge Functions

Use PostgreSQL RPC for task, deadline, excuse, payment, ledger, correction, membership, rule, timezone, and pause transitions because their locks, authorization, and side effects must be atomic. Edge Functions are appropriate for FCM delivery, trusted Auth-admin provisioning/reset orchestration, and future external APIs that require secrets.

An Edge Function authenticates or verifies its trusted scheduler invocation, validates inputs, uses narrowly scoped credentials where possible, and calls database domain functions rather than duplicating business rules. It must not calculate authoritative debt, completion, or review outcomes independently. External failure is isolated through an outbox and cannot roll back committed domain truth.

## 18. Background Workers

`materialize_open_tasks`, `close_due_tasks`, and `dispatch_notification_outbox` are not executable by `anon` or ordinary `authenticated` clients. Invoke them through trusted schedules/service identities with explicit environment and operation scope. If a user-facing catch-up is needed, expose a separate bounded function that can materialize only the caller's currently eligible rows.

Workers derive challenge/user targets from database queries, use server time, claim bounded batches with locks, and rely on unique sources/idempotency for retries. They must not accept arbitrary challenge or beneficiary parameters from an untrusted caller. Record correlation, counts, duration, and safe failures; alert on repeated batch failure, stale locks, or growing backlog.

## 19. Common Attack and Failure Cases

| Case | Required mitigation |
|---|---|
| User changes phone clock/timezone | Ignore for authority; compare one server instant with frozen windows |
| User edits request `user_id` | Derive actor from `auth.uid()` and ownership from locked rows |
| User calls RPC for another person's task | Task-owner and active-membership check inside RPC |
| Participant directly updates task status/time | RLS/column grants deny; authoritative writes only through RPC |
| Participant manually calls admin RPC | Function checks active admin grant in target challenge |
| Admin approves/rejects own excuse | Resolve participant and reject actor equality server-side |
| Admin approves/rejects own payment | Resolve requester and reject actor equality server-side |
| Admin reduces own debt | Resolve ledger beneficiary and reject actor equality |
| Admin beneficially corrects own task | Server classifies old/new transition and requires different admin |
| Duplicate completion/progress call | Request-key uniqueness, task lock, and terminal-state constraint |
| Replayed payment approval | Payment lock, pending compare-and-set, unique ledger source/request |
| Forged historical timestamp/evidence | Accept only referenced pre-existing trusted server evidence |
| Guess/enumerate another challenge's UUID | RLS and RPC challenge authorization on every access |
| Broad Realtime subscription | RLS-filtered publications and narrow columns/views |
| Device token exposed to participant/admin | No base-table client read; protected storage and log redaction |
| Sensitive push visible on lock screen | Generic payload; details require authenticated in-app view |
| Service-role key bundled in Flutter | Build/repository secret scanning and deployment review; rotate on exposure |
| Unsafe definer `search_path` or grants | Fixed path, qualified objects, non-login owner, revoke `PUBLIC`, narrow execute |
| Deadline worker races completion | Same row lock, server-time recheck, one terminal transition/source |
| FCM outage or poison token | Transactional outbox, bounded retry/dead state, disable invalid token |
| Stale client role/debt/status | Re-read authoritative state after locks and return typed conflict |

## 20. Implementation Order

1. Establish Supabase Auth/profile linkage and private provisioning/password-reset boundaries.
2. Add reusable challenge membership/admin authorization helpers.
3. Enable RLS with deny-by-default policies on every application table.
4. Add least-privilege read policies, restricted views, and column exposure.
5. Implement controlled participant/admin RPC mutations with locks and idempotency.
6. Implement immutable ledger and transactional payment/waiver functions.
7. Enforce independent review and beneficial-self-action prohibitions server-side.
8. Secure device registration, notifications, outbox, and secret-bearing delivery.
9. Add only RLS-safe Realtime publications.
10. Run the full role/action/time/race security test suite before production data.

## 21. Security Test Plan

Future automated tests must call both the intended RPCs and direct Data API paths with realistic JWT roles:

1. Participant cannot read rows from another challenge.
2. Participant cannot read another participant's private task, finance, excuse, payment, or notification rows.
3. Participant cannot mutate another participant's task.
4. Participant cannot directly set task progress, outcome, target, or authoritative timestamps.
5. Participant cannot approve/reject a payment or excuse.
6. Admin cannot approve or reject their own payment; it remains pending.
7. Admin cannot approve or reject their own excuse; it remains pending.
8. Admin cannot waive or negatively adjust their own penalty/debt.
9. Admin cannot beneficially correct their own historical task.
10. Active admin can perform each permitted action for another participant in the same challenge.
11. Admin of challenge A cannot manage or inspect private records in challenge B.
12. Revoked admin immediately loses management/review authority.
13. Device time/timezone and forged client timestamps do not change eligibility or ranking time.
14. On-time correction fails without qualifying pre-deadline server evidence.
15. Duplicate/replayed RPC calls create one logical completion, review, ledger, audit, and notice effect.
16. Concurrent completion/deadline and competing review races converge to one valid terminal result.
17. Ledger entries cannot be directly inserted, edited, or deleted, including by an ordinary admin session.
18. Payment approval revalidates current debt and cannot overpay or cross currencies/challenges.
19. Raw device tokens cannot be read across users or by challenge admins.
20. Notification outbox cannot be read or written by client roles.
21. Audit rows cannot be inserted, updated, or deleted by client roles.
22. Realtime subscriptions expose only the same rows/columns permitted by RLS.
23. Missing/invalid identity, challenge scope, role, or worker secret fails closed.
24. Definer functions cannot resolve attacker-controlled objects through `search_path` and are not executable by unintended roles.

## 22. Decisions and Risks

### Key decisions

- PostgreSQL is the authoritative security and transaction boundary; RLS controls visibility and narrow RPCs control sensitive writes.
- Identity, participation, and the full MVP admin grant are separate.
- Privileged self-review/self-benefit has no sole-admin bypass and requires a different active challenge admin.
- Time, finance, corrections, audit, and notification delivery use server-generated, append-oriented evidence.
- Edge Functions handle secret-bearing external work, not core transactional decisions.

### Residual risks

The highest risks are a missing predicate in a definer function, overly broad RLS/Realtime publication, timezone/deadline race defects, incorrect beneficial-correction classification, compromised privileged credentials, and sensitive data in logs/push/audit. A sole participating admin can intentionally leave their own requests unresolved; this is accepted product behavior, not an authorization exception.

### Future hardening

Add automated policy-diff tests, database role linting, secret scanning, rate limits and abuse detection, step-up authentication for high-impact finance/admin actions, operational audit export/retention, restore drills, and a V2 delegated trusted-reviewer model only after product approval.

### Migration assumptions

Migrations must enforce RLS on all 22 tables; deny direct authoritative writes; create narrow grants/views; encode active challenge scope, reviewer/beneficiary independence, immutable history, evidence rules, uniqueness/idempotency, and challenge currency/time constraints; and protect every definer/worker entry point. No migration may weaken these invariants for convenience.
