# Business Rules

## 1. Scope and Authority

This document defines testable product rules for challenge membership, obligations, completion, penalties, payments, ranking, reminders, and corrections. [PRODUCT_SPEC.md](PRODUCT_SPEC.md) defines product purpose, journeys, scope, and entities. `AGENTS.md` remains the concise invariant authority; a conflict must be resolved explicitly rather than implemented silently.

## 2. Challenge, Roles, and Access

- **BR-001:** Every obligation, rule version, ledger transaction, payment request, ranking result, and challenge-scoped notification must reference exactly one challenge.
- **BR-002:** A challenge has a name, description, effective-dated timezone, start date, optional end date, lifecycle status, one authoritative currency, and at least one authorized sardor when activated.
- **BR-003:** The minimum lifecycle is `DRAFT`, `ACTIVE`, `PAUSED`, and `ENDED`. Only `ACTIVE` challenges open new obligation periods; every pause interval is audited.
- **BR-004:** MVP access is private. Participants cannot freely self-register into or join a challenge.
- **BR-005:** For MVP, an admin provisions a unique participant login and temporary password. The participant must replace it on first successful login and may later change it; an authorized admin may reset credentials but cannot retrieve an existing plaintext password.
- **BR-006:** User identity, challenge participation, and administrative authorization are separate concepts.
- **BR-007:** A user may simultaneously be a ranked participant and an admin/sardor in the same challenge.
- **BR-008:** Participation never grants administrative authority. Every administrative mutation requires an explicit server-verified role or permission.
- **BR-009:** Ordinary participants cannot manage membership or rules, correct history, waive penalties, approve payments, or access admin-only monitoring.
- **BR-010:** Admin participation uses the same obligation, penalty, and ranking rules as other participants; admin status provides no ranking advantage. MVP may assign the same full challenge-level `ADMIN`/`SARDOR` role to multiple users; granular moderator permissions are V2.

## 3. Membership and Eligibility

- **BR-011:** Membership records require effective timing and a state sufficient to distinguish active, inactive, and removed participation without deleting history.
- **BR-012:** A participant is eligible only for obligation periods that open on or after their effective join time and while membership is active, subject to pause and excuse rules. Effective deactivation/removal opens no new obligations and neutralizes incomplete obligations that are no longer actionable.
- **BR-013:** The system must not generate missed obligations for periods before a participant joined.
- **BR-014:** Removing or deactivating a participant is logical, not physical, whenever obligations, activity, audit, ranking, or finance records reference them. Historical debt and payment records remain intact, and the membership change is audited.
- **BR-015:** Inactive or removed participants retain read access only as allowed by the challenge's product policy and authorization rules; historical records remain intact.
- **BR-016:** An excused miss remains historically visible as not completed but justified. It is excluded from the primary completion-rate denominator, grants no completion credit, creates no net penalty, and is neutral for the daily discipline streak.

## 4. Habits, Rules, and Periods

- **BR-017:** A habit has a stable identity and one recording type: boolean/checkbox, quantity/counter, duration, daily occurrence, or weekly target.
- **BR-018:** A boolean habit is fulfilled by one valid confirmation during its active period. A daily occurrence is a once-per-daily-period scheduled obligation, even if its recording interaction is checkbox-like.
- **BR-019:** A quantity habit has a positive target and supports partial authoritative progress during the active period. Example: reading progresses from `3/10` to `7/10` to `10/10`.
- **BR-020:** MVP duration progress is self-reported/manual. It accumulates accepted duration toward the configured target; GPS, wearables, sensors, and background stopwatch verification are not required.
- **BR-021:** A weekly target accumulates valid occurrences or units within one weekly period. For occurrence habits such as Gym, at most one occurrence per challenge-local calendar day counts toward the target.
- **BR-022:** Each habit rule is versioned and effective-dated. It contains the applicable cadence, window, target, penalty terms, and reminder terms.
- **BR-023:** Rule versions for the same habit must not overlap for the same effective scope.
- **BR-024:** An obligation binds to the rule version effective when its period opens. Later rule edits cannot alter that obligation's target, deadline, penalty, or reminder history.
- **BR-025:** Daily boundaries use the challenge timezone. The MVP challenge week is Monday 00:00 through Sunday 23:59:59 in that timezone; boundaries are represented and compared using authoritative server timestamps.
- **BR-026:** A period has `opens_at` and `deadline_at`, with `deadline_at > opens_at`. Fajr may use 05:00–06:30; Reading may use 00:00–23:00.
- **BR-027:** New effective-dated rules may increase a target or add a habit prospectively without regenerating or rewriting prior obligations.

## 5. Time, Progress, and Completion

- **BR-028:** Server time is the sole authority for opening windows, accepting progress/completion, assigning timeliness, applying penalties, and calculating ranking timing.
- **BR-029:** Client timestamps, local timezone, and device clock are informational only and cannot establish validity. Changing a phone clock provides no advantage.
- **BR-030:** A normal participant may mutate only their own obligation while the server determines it is open and eligible.
- **BR-031:** Partial progress is accepted only during the active window. Each operation must be authenticated, challenge-scoped, non-negative, and idempotent.
- **BR-032:** Progress cannot be reduced or reassigned by a normal participant. Corrections use the audited admin path.
- **BR-033:** The authoritative completion time is the server timestamp at which accepted progress first reaches the target, or at which a valid boolean/daily occurrence is accepted.
- **BR-034:** Progress beyond a target may be retained for analytics, but it does not create extra completion credit unless a future rule explicitly defines it.
- **BR-035:** A normal participant cannot complete or add progress after `deadline_at` and cannot backdate an operation. A server-accepted event exactly at `deadline_at` is on time.
- **BR-036:** Authoritative completion requires a successful server submission by the deadline. Offline local actions may be shown as unsynced drafts but cannot establish completion or timeliness; a participant cannot later backdate them. Audited admin correction is the only exception path.
- **BR-037:** Past periods are read-only for normal participants.

## 6. Obligation Statuses and Transitions

- **BR-038:** Every obligation uses one of at least: `PENDING`, `COMPLETED_ON_TIME`, `MISSED`, `COMPLETED_LATE`, or `EXCUSED`.
- **BR-039:** A newly opened eligible obligation starts `PENDING`.
- **BR-040:** A participant can cause only `PENDING -> COMPLETED_ON_TIME`, through a valid server-accepted completion at or before the deadline.
- **BR-041:** Partial progress that remains below target does not change `PENDING` status.
- **BR-042:** After the deadline, the system deterministically changes an incomplete eligible `PENDING` obligation to `MISSED` exactly once.
- **BR-043:** `COMPLETED_LATE` is not available to normal participants. It records an audited admin-recognized late outcome and does not count as on-time fulfillment.
- **BR-044:** `EXCUSED` means the obligation was not completed but its miss was approved or neutralized. It is never equivalent to `COMPLETED_ON_TIME` and requires an authorized admin decision or deterministic audited policy such as pause/deactivation.
- **BR-045:** Admin corrections may establish `COMPLETED_ON_TIME`, `COMPLETED_LATE`, `MISSED`, or `EXCUSED` only through an append-only correction event that preserves the previous state. `COMPLETED_ON_TIME` additionally requires the authoritative evidence defined in BR-143–BR-145.
- **BR-046:** Repeating the same transition request must not create duplicate completion, correction, activity, or penalty effects.

## 7. Penalties and Financial Ledger

- **BR-047:** When an eligible uncovered obligation becomes `MISSED`, the system creates the penalty defined by its bound rule version exactly once. Approved excuse coverage suppresses that penalty only for the covered obligation or units.
- **BR-048:** Financial truth is a challenge-scoped append-only ledger. A mutable debt field must not be the sole source of truth.
- **BR-049:** MVP ledger transaction concepts are `PENALTY`, `PAYMENT_CONFIRMED`, `WAIVER`, and `ADMIN_ADJUSTMENT`.
- **BR-050:** Every transaction identifies challenge, participant, challenge currency, amount/effect, reason or source, authoritative timestamp, and an idempotent source reference.
- **BR-051:** Current challenge debt is derived from ledger effects. Historical penalty total, total paid, and current outstanding debt are separate metrics.
- **BR-052:** Transactions are never silently deleted or edited. Reversals, waivers, and corrections append compensating transactions linked to their reason and actor.
- **BR-053:** If a missed obligation is later corrected to on-time or excused, the original penalty remains historical and any debt relief is an explicit linked `WAIVER` or adjustment. A waiver changes financial accountability only; it cannot manufacture on-time completion or ranking evidence.
- **BR-054:** MVP weekly penalties use `PER_MISSING_UNIT`. The rule version records the mode explicitly so `FIXED_IF_TARGET_MISSED` can remain a supported future product concept without complicating MVP behavior.
- **BR-055:** For `PER_MISSING_UNIT`, penalty equals `missing units × penalty per unit`. For Gym target 3 at 50,000 UZS/unit: `3/3 = 0`, `2/3 = 50,000`, `1/3 = 100,000`, and `0/3 = 150,000`.
- **BR-056:** Future `FIXED_IF_TARGET_MISSED` semantics would create one configured fixed penalty when progress is below the eligible target; it is not required for MVP.
- **BR-057:** Missing weekly units are evaluated only at the weekly deadline against the visible eligible target; partial weekly progress must not create early penalties.

## 8. Payment Requests

- **BR-058:** Payment requests are declarations for manual admin confirmation, not card or bank transactions.
- **BR-059:** The Pay action and payment form are hidden when the selected challenge debt is zero or negative.
- **BR-060:** A request explicitly references one challenge and one requesting participant.
- **BR-061:** At submission, the server requires `amount > 0` and `amount <= current outstanding debt` for that challenge.
- **BR-062:** MVP permits at most one `PENDING` payment request per participant per challenge.
- **BR-063:** Submitting a request creates `PENDING`, records an authoritative timestamp, and notifies eligible admins; it does not create a ledger transaction or reduce debt.
- **BR-064:** Only an explicitly authorized active admin may approve or reject a request. A participating admin cannot derive this authority from participation and cannot review their own payment request.
- **BR-065:** Approval revalidates current challenge debt and the request state inside the same transaction that creates `PAYMENT_CONFIRMED`, records reviewer and `reviewed_at`, and marks the request `APPROVED`.
- **BR-066:** Repeating a successful approval must not create another ledger entry.
- **BR-067:** If the requested amount exceeds current debt at approval time, approval fails without changing the request or ledger. The admin must resolve it, for example by rejecting it so the participant can submit a valid amount.
- **BR-068:** Rejection records `REJECTED`, reviewer, `reviewed_at`, and an optional reason; it never changes debt.
- **BR-069:** Approval and rejection notify the participant. Example admin alert: “Kamron submitted a 100,000 UZS payment for approval.”
- **BR-070:** Cross-challenge debt may be displayed as an aggregate in the future, but requests, approvals, and ledger accounting remain challenge-scoped.

## 9. Ranking

- **BR-071:** Ranking's primary measure is completion rate over closed periods: `COMPLETED_ON_TIME eligible obligations / closed eligible obligations`.
- **BR-072:** An obligation enters official ranking calculations only after its deadline has passed. All obligations from still-open periods—including early completions—are excluded so early completion gives no temporary completion-rate bonus.
- **BR-073:** `MISSED` and `COMPLETED_LATE` remain non-fulfilled eligible outcomes. An excused miss is excluded from numerator and denominator, grants no positive ranking points, and is reported separately. Paused, pre-join, and applicable post-inactive periods are likewise neutral.
- **BR-074:** Higher completion rate always outranks lower completion rate. Timing cannot compensate for a missed obligation.
- **BR-075:** When completion rates are equal, compare mean normalized completion timing across comparable `COMPLETED_ON_TIME` obligations with authoritative completion timestamps: `(completed_at - opens_at) / (deadline_at - opens_at)`; lower is earlier.
- **BR-076:** Quantity and duration habits use the authoritative time the target first became complete, not the first partial-progress time.
- **BR-077:** If completion performance and normalized timing are equal or unavailable, participants share the same rank; any alphabetical display order is presentation-only.
- **BR-078:** A participant with no closed eligible obligations is shown as not yet ranked rather than assigned a misleading 0% or 100%.
- **BR-079:** Rankings must expose completed, excused-miss, and unexcused-miss counts separately, plus eligible denominator, completion rate, timing tie-break, and exclusions. For example, `98 completed + 2 excused` may yield `98/98 = 100%`, but must never display as `100/100 completed`.
- **BR-080:** Preserve rule bindings, windows, statuses, and timestamps so historical rankings can be recomputed.

Example: Aziz completes 100/100 near each deadline; Kamron completes 98/100 earlier. Aziz ranks above Kamron because 100% outranks 98%. If both complete 100/100, lower average normalized completion timing wins.

## 10. Reminders, Activity, and Notifications

- **BR-081:** User-configurable categories are habit reminder, deadline warning, and team activity. Additional important events include penalty creation, applicable payment submission, payment approval/rejection, important admin correction, and excuse approval/rejection.
- **BR-082:** User-selectable delivery modes are `PUSH_AND_IN_APP`, `IN_APP_ONLY`, and `DISABLED` where applicable. Default is push plus in-app when platform permission exists; push follows platform permission and applicable settings, while authoritative event history remains in-app.
- **BR-083:** A habit rule may define reminder start, reminder end, interval, default template, and optional admin-edited template.
- **BR-084:** Reminder timing is evaluated in the challenge timezone using the bound rule version and authoritative time.
- **BR-085:** Stop reminders when the obligation completes or its reminder/deadline window ends. Never send stale reminders after the window.
- **BR-086:** Different habits have independent schedules. A Fajr window of 05:00–06:30 cannot inherit Reading's evening reminder schedule.
- **BR-087:** Reading with deadline 23:00 may schedule reminders at 21:00, 21:30, 22:00, and 22:30 when configured; any remaining reminders stop immediately after completion.
- **BR-088:** A valid completion may create one team activity event containing participant, habit, completion time, event type, and challenge.
- **BR-089:** App-open feeds may receive Supabase Realtime updates. App-closed/background alerts require push delivery; Realtime is not a push substitute.
- **BR-090:** Completion feedback may use a brief, tasteful celebration. It must not obstruct the next action or become excessive.
- **BR-091:** The MVP avoids spam through category preferences, deduplication, and completion/window suppression. Every important event from BR-081 creates an in-app history record even when push is unavailable; digest delivery is a future option.

Example activity: “Kamron completed Gym.”

## 11. Admin Corrections and Audit

- **BR-092:** Historical correction requires explicit administrative permission, a target record, reason, actor, authoritative `recorded_at`, old state, and new state. Any claimed historical completion time must satisfy BR-143–BR-145, and any self-benefiting correction must satisfy BR-155–BR-157.
- **BR-093:** A correction preserves the previous state and appends the new decision; it does not erase the original fact.
- **BR-094:** Habit-rule changes, task corrections, penalty waivers/adjustments, payment decisions, and important membership changes produce immutable audit events.
- **BR-095:** An admin must not perform a historical correction on their own task when it would improve their completion, accountability, or ranking outcome. A different active challenge admin must perform and audit that correction.
- **BR-096:** UI visibility, client role claims, or challenge membership alone never authorize a correction.

Example: Sardor excuses Aziz's missed Fajr after reviewing a valid reason. The obligation records an audited transition to `EXCUSED`; its original penalty remains, and a linked waiver offsets it.

## 12. Concurrency and Idempotency

- **BR-097:** Progress updates, completion, deadline closure, penalty creation, payment submission/review, and admin corrections require stable idempotency handling.
- **BR-098:** Database constraints should prevent duplicate obligation periods, duplicate source-linked ledger transactions, multiple pending requests for the same user/challenge, and repeated terminal payment decisions.
- **BR-099:** Operations that change both workflow state and ledger/audit effects are transactional: either every required effect commits or none does.
- **BR-100:** Server-side logic must re-read authoritative state at mutation time and reject stale or unauthorized commands rather than trusting client-cached debt, status, role, or deadline data.
- **BR-101:** Concurrent attempts to complete the same obligation may return the already-established result but cannot create duplicate activity or financial effects.
- **BR-102:** Scheduled deadline processing must be safely repeatable and converge on one missed status and one applicable penalty per obligation.

## 13. Statistics

- **BR-103:** Participant statistics distinguish completion rate, completed obligations, unexcused misses, excused misses, current daily discipline streak, best streak, penalty count, total penalty amount, total paid, outstanding debt, normalized timing, and rank. Excused history supports breakdown by habit, reason, and timeline.
- **BR-104:** Financial statistics are calculated per challenge. A cross-challenge aggregate, if later shown, is a derived display and never an accounting boundary.
- **BR-105:** Conceptual filters include today, 7 days, 30 days, challenge lifetime, custom range, habit, and participant, subject to permissions.
- **BR-106:** Admin monitoring includes today's completion state, pending/missed habits, upcoming deadlines, participant attention indicators, debts, and payment requests.
- **BR-107:** Statistics must use the same eligibility, status, and exclusion rules as ranking and finance; dashboards cannot maintain conflicting independent totals.

## 14. Excuse Requests and Excused Misses

- **BR-108:** A participant may request an excuse for a defined start/end range within one challenge and for an explicit non-empty set of that participant's habits. Unselected habits remain due.
- **BR-109:** MVP reason categories are `BUSINESS_TRIP`, `TRAVEL`, `ILLNESS`, `FAMILY_EMERGENCY`, `ADMIN_APPROVED_OTHER`, and `OTHER`. `OTHER` requires explanatory text; other categories may accept optional text unless policy requires it.
- **BR-110:** An excuse request starts `PENDING` and records participant, challenge, requested range, requested habits, reason, reason text when applicable, and authoritative `submitted_at`.
- **BR-111:** Excuse request decisions are `APPROVED` or `REJECTED` and require a different explicitly authorized admin, authoritative `reviewed_at`, reviewer, and auditable decision context. `reviewed_by` must never identify the excuse participant.
- **BR-112:** Before approval, an admin may narrow the covered habits. The approved set must be shown clearly to the participant and audit history must preserve both requested and approved sets.
- **BR-113:** An approved request creates excuse coverage only for obligations whose habit and active period fall within the approved scope. It is not a whole-day exemption unless every relevant habit was explicitly approved.
- **BR-114:** Pre-deadline approval does not immediately mark a still-open obligation completed or excused. If the participant completes it on time, it becomes `COMPLETED_ON_TIME`; otherwise, after the deadline it becomes `EXCUSED` rather than `MISSED`.
- **BR-115:** A pre-approved covered excused miss creates no penalty, is excluded from the primary completion-rate denominator, is neutral for streaks, and remains visible as not completed and excused.
- **BR-116:** Rejected requests provide no excuse coverage and do not alter obligation, ranking, streak, or financial outcomes.
- **BR-117:** A participant may submit a late excuse after an obligation became `MISSED`, subject to the same review and audit requirements.
- **BR-118:** Approving a late excuse appends an audited correction to `EXCUSED`; it never rewrites the fact that the deadline process originally marked the obligation missed.
- **BR-119:** If a late-approved obligation already created a penalty, preserve the original `PENALTY` and append a linked compensating `WAIVER` or adjustment so derived debt is correct.
- **BR-120:** Rejecting a late excuse leaves the missed status, penalty, debt, and ranking effects unchanged while preserving the reviewed request.
- **BR-121:** Excuse history exposes date/period, habit, not-completed outcome, approved reason, and decision context to authorized participants and admins. Statistics separately report total excused misses and breakdowns by habit and reason.
- **BR-122:** Excuse submission, review, coverage application, status correction, and financial compensation must be idempotent and safe under concurrent deadline or review processing.

Example: Kamron requests September 12–15 coverage for Fajr and Gym due to a business trip. Reading, Salawat, and Istighfar remain due. If the admin approves only Gym, an incomplete Fajr is still an unexcused miss; covered incomplete Gym history is shown as “Not completed — Excused — Business trip.”

## 15. Weekly Excuse Adjustments

- **BR-123:** For a weekly habit, an approved excuse may specify a non-negative number of excused units, capped at the original target.
- **BR-124:** `eligible target = original target - approved excused units`. The system preserves and displays original target, excused reduction, eligible target, and actual counted completion count.
- **BR-125:** Weekly satisfaction and penalties use the eligible target. With original Gym target `3`, excused units `2`, and actual count `1`, the eligible target is `1`, the obligation is completed against its eligible requirement, and penalty is zero.
- **BR-126:** Approved unit reduction grants no completion units. It only removes covered units from what is eligible and required. If eligible target becomes zero and actual completion count is zero, the outcome is `EXCUSED`, not completed.
- **BR-127:** Under `PER_MISSING_UNIT`, weekly penalty equals `max(eligible target - actual counted completion count, 0) × penalty per unit`.

## 16. Effective Changes, Pause, Currency, and Streaks

- **BR-128:** A timezone change is effective-dated and applies only to periods that have not opened. It cannot reinterpret historical windows or recalculate historical completions, penalties, or ranking facts.
- **BR-129:** On effective deactivation/removal, no new obligations open. Existing incomplete obligations that are no longer fairly actionable become neutral `EXCUSED` outcomes through an audited membership policy; completed and historical financial records remain unchanged.
- **BR-130:** Starting a challenge pause is audited, invalidates currently `PENDING` obligations as neutral `EXCUSED` outcomes, and prevents new obligations from opening until audited resumption. Already completed obligations remain completed.
- **BR-131:** Each challenge has exactly one authoritative currency, defaulting to UZS. All its penalties, ledger entries, debts, and payment requests use that currency.
- **BR-132:** After the challenge's first ledger transaction, its currency cannot change in MVP.
- **BR-133:** A daily discipline day succeeds only when it contains at least one eligible required daily obligation and all such obligations are `COMPLETED_ON_TIME`.
- **BR-134:** `MISSED` or `COMPLETED_LATE` on any eligible required daily obligation makes that day unsuccessful and breaks the daily discipline streak.
- **BR-135:** Excused or pause-neutral obligations are ignored when evaluating the day. A day with no remaining eligible required daily obligations is neutral: it neither increments nor breaks the streak.
- **BR-136:** Weekly target habits do not directly increment or break the daily discipline streak. Current and best streak calculations must preserve neutral days without treating them as successful days.

## 17. Independent Excuse Review

- **BR-137:** An admin/sardor who participates may submit an excuse request under the same participant rules as anyone else.
- **BR-138:** An admin must never approve or reject their own excuse request. For every terminal review, `reviewed_by` must differ from the excuse participant.
- **BR-139:** The server must enforce independent review; hiding or disabling controls in the client is insufficient.
- **BR-140:** If the requester is the challenge's only admin, the request remains `PENDING`. They cannot approve or reject it, and a different full challenge admin must be added before review can finish.
- **BR-141:** Every independent review remains auditable under BR-111. MVP does not add participant voting, a moderator role, or a granular permission matrix to solve reviewer availability.
- **BR-142:** A trusted-reviewer or delegated-review workflow may be considered in V2, but it grants no authority in MVP.

## 18. Historical Completion Evidence

- **BR-143:** A historical correction may be `COMPLETED_ON_TIME` only when trusted server-side evidence already exists and proves the target was reached at or before `deadline_at`.
- **BR-144:** Qualifying evidence includes an existing server-recorded completion/event, server-recorded progress proving the target was reached, or another trusted system record created by the deadline. The correction must reference the evidence rather than replace it.
- **BR-145:** A client clock, manually entered historical timestamp, user statement alone, editable local metadata, or screenshot of a device clock is not authoritative timing evidence.
- **BR-146:** Without qualifying pre-deadline evidence, an admin may acknowledge reported completion only as `COMPLETED_LATE`, with correction reason, actor, authoritative `recorded_at`, old state, and new state.
- **BR-147:** A `COMPLETED_LATE` correction must not fabricate or backdate `completed_at`. It receives no artificial on-time or early normalized timestamp and cannot improve the completion-timing tie-breaker as though submitted on time.
- **BR-148:** An authorized admin may separately waive an associated penalty when justified, but never their own penalty/debt. The linked waiver affects debt only and does not convert `COMPLETED_LATE` to `COMPLETED_ON_TIME` or alter ranking-time evidence.
- **BR-149:** Completion recognition, timing classification, penalty accountability, and ranking evidence are separate audited decisions and must not be inferred from one another.

Example: a task deadline was 23:00 and no server completion exists. The next morning, Aziz says he completed it at 21:00 but forgot to submit. Sardor may record `COMPLETED_LATE`, the report reason, and an optional linked waiver, but must not create `completed_at = 21:00` without pre-existing trusted server evidence.

## 19. Privileged Self-Review Separation

- **BR-150:** An admin/sardor who is also a participant must not use privileged authority to review or beneficially alter their own participant-specific accountability or financial records.
- **BR-151:** This restriction does not prevent an admin from completing current tasks normally, submitting their own excuse/payment requests, or managing challenge-wide habits, rules, and settings under ordinary audited admin authority.
- **BR-152:** Excuse approval/rejection requires a different active challenge admin; BR-137–BR-142 continue to apply.
- **BR-153:** Payment approval/rejection requires `reviewed_by` to identify a different active challenge admin from the payment participant. Submission by a participating admin remains allowed and never reduces debt.
- **BR-154:** A `WAIVER` or negative `ADMIN_ADJUSTMENT` that reduces a participant's penalty/debt must be authorized by an active admin other than that beneficiary.
- **BR-155:** A historical task correction that improves completion, accountability, or ranking for a participating admin requires a different active challenge admin. Improvement includes any more favorable recorded outcome or ranking evidence; penalty relief remains separately governed by BR-154.
- **BR-156:** If no different active admin exists, an admin's own excuse/payment request remains `PENDING`, and a self-benefiting waiver/correction remains unresolved. Another active full challenge admin must be added before the privileged action can occur.
- **BR-157:** Secured server-side functions must enforce reviewer/actor independence after resolving the target participant or financial beneficiary. Client-side hiding, disabled controls, or client role claims are insufficient.
- **BR-158:** Every such review, waiver, adjustment, or correction remains auditable with actor, beneficiary/participant, challenge, target, old/new state where applicable, reason, and authoritative time.
- **BR-159:** MVP adds no participant voting, moderator role, granular permission matrix, or special bypass for a sole admin. A future trusted-reviewer/delegated-review workflow remains V2 only.

## 20. Open Questions

None currently.
