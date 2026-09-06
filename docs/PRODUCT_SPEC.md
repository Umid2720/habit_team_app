# Product Specification

## 1. Product Vision

The product is a private Android and iOS habit/accountability app for teams running structured challenges. A team leader (`sardor`, or admin) provisions access, defines habits and rules, and monitors progress. Participants complete time-bound obligations, see team activity and rankings, and remain accountable for missed-habit penalties. The admin may also participate and rank under the same participant rules.

The product should make consistent action visible, make missed obligations difficult to ignore, and preserve a trustworthy history. It should feel calm, serious, and premium rather than like a generic checklist.

Detailed deterministic behavior is defined in [BUSINESS_RULES.md](BUSINESS_RULES.md).

## 2. Goals

1. Help teams build habits consistently through clear daily and weekly obligations.
2. Prevent silent abandonment with deadlines, missed statuses, reminders, and financial accountability.
3. Motivate participants through timely team activity, understandable statistics, and fair rankings.
4. Give admins practical monitoring and audited correction tools.
5. Preserve reproducible rule, completion, ranking, and financial history.
6. Make authoritative decisions securely using server time and server-side authorization.

## 3. Non-Goals for MVP

- Public registration, public challenge discovery, or open join links.
- Card processing, bank integration, or automatic money movement.
- A separate admin application.
- Social networking beyond the private challenge activity feed.
- AI coaching, wearable integrations, or complex gamification.
- GPS, sensor verification, or background stopwatch tracking for duration habits.
- Offline-authoritative completion or client-generated completion timestamps.
- Pixel-level UI specification in this document.

## 4. Personas and Roles

### Admin / Sardor

Creates and manages challenges; provisions participant access; manages membership, habits, effective-dated rules, targets, deadlines, penalties, and reminders; monitors activity and statistics; reviews excuse and payment requests; performs explicit audited corrections; and resets credentials. An admin may narrow the habits covered by an excuse before approval when the UI clearly communicates the change. The MVP may have multiple admins using the same full challenge-level role, but an admin can never review their own excuse request. Admin authority is separate from participation. When an admin participates, their obligations and ranking are evaluated exactly like any other participant's.

### Participant

Uses an admin-provisioned username and temporary password, replaces that password on first successful login, views current obligations, records progress, completes eligible tasks, follows team activity and rankings, reviews penalties and challenge debt, submits excuse and payment requests, and configures notification preferences. A participant cannot mutate administrative data or edit history.

## 5. Primary User Journeys

### 5.1 Challenge setup

1. A sardor creates a challenge with name, description, timezone, start date, and optional end date.
2. The sardor provisions each participant with a unique login and temporary password. MVP uses one full challenge-level admin role; granular moderator permissions are deferred.
3. The sardor creates habits and effective-dated rules containing schedule, target, deadline, penalty, and reminder configuration.
4. Participants sign in and see obligations generated only for periods in which they are eligible.

### 5.2 Daily participation

1. A participant opens **Today** and sees pending, completed, or missed obligations and current progress.
2. For quantity or duration habits, the participant records partial progress while the window is open.
3. A valid server submission that reaches the target completes the obligation.
4. The app gives restrained immediate positive feedback and publishes eligible team activity.
5. After the deadline, incomplete obligations become missed and penalties are recorded when configured.

### 5.3 Weekly target

A participant sees the weekly target, accumulated progress, remaining units, and period end. The MVP challenge week runs Monday 00:00 through Sunday 23:59:59 in the challenge timezone, and at most one occurrence per challenge-local calendar day counts. After the deadline, the system evaluates missing eligible units and creates the configured per-missing-unit penalty.

### 5.4 Payment declaration

1. From **Debt / Finance**, a participant selects a challenge with positive debt.
2. They submit an amount no greater than that challenge's current debt.
3. The request remains pending without changing debt.
4. An authorized admin approves or rejects it.
5. Only approval creates a confirmed payment ledger entry; both outcomes notify the participant.

### 5.5 Excuse request

1. A participant requests an excuse for a defined time range, selects affected habits, and supplies a reason.
2. Unselected habits remain due; an excuse is not automatically a whole-day exemption.
3. A different authorized admin approves, rejects, or clearly narrows the selected habits before approval. The requester cannot review their own request.
4. An approved uncovered miss remains visibly not completed but justified, carries no applicable penalty, and is neutral in completion rate and daily discipline streak.
5. If approval follows a miss and penalty, the original facts remain and a compensating waiver corrects debt.

If the requester is the challenge's only admin, the request remains pending until another full challenge admin is added. MVP does not introduce participant voting or a moderator role for this case.

### 5.6 Admin monitoring and correction

The admin reviews today's status, pending and missed habits, upcoming deadlines, at-risk participants, debts, and pending payments. A historical correction requires an explicit reason and produces an audit record preserving actor, `recorded_at`, old state, and new state. It may be `COMPLETED_ON_TIME` only when an existing trusted server-side record proves the target was reached by the deadline. Without that evidence, an acknowledged completion is `COMPLETED_LATE`; a separate penalty waiver cannot convert its timing or ranking evidence to on-time.

## 6. Information Architecture

### Participant navigation

- **Today:** current obligations, progress, deadlines, and completion feedback.
- **Team:** realtime challenge activity and announcements.
- **Ranking:** fair standings, supporting metrics, and explanation.
- **Debt / Finance:** challenge-scoped penalties, payments, outstanding debt, and payment requests.
- **Profile:** password change and notification preferences.

### Admin capabilities

Admin functions remain in the same app and may be grouped behind role-aware entry points:

- Dashboard and monitoring
- Participants and membership
- Habits, rules, schedules, and reminders
- Payments and penalties
- Audit history
- Challenge settings

Navigation visibility is not authorization; all protected actions require server-side permission checks.

## 7. Feature Inventory

### Challenge and membership

- Private challenge creation and lifecycle
- Admin-provisioned access
- Active/inactive/removed membership history
- Multiple admins with explicit permissions
- Audited pause periods and effective-dated timezone changes
- Habit-selective excuse requests, review, and excused-miss history

### Habits and obligations

- Boolean/checkbox, quantity/counter, duration, daily-occurrence, and weekly-target habits
- Daily and weekly periods with challenge-timezone windows
- Partial progress for quantity habits
- Versioned/effective-dated targets, penalties, deadlines, and reminders
- Explicit obligation statuses and immutable historical context

### Accountability

- Automatic missed evaluation
- Approved pre-deadline and late-excuse handling without representing a miss as completion
- Challenge-scoped append-only financial ledger
- Payment declaration and admin confirmation
- Completion-first rankings and historical statistics
- Audited admin corrections

### Communication

- In-app and push reminders/warnings
- Realtime app-open team activity
- Push notifications for background delivery
- Notification category preferences
- Restrained completion celebration

### Statistics and monitoring

Participant views may show completion rate, completed obligations, unexcused misses, excused misses, current and best daily discipline streak, penalty count/amount, total paid, outstanding debt, normalized completion timing, and rank. Excused history supports habit, reason, and timeline views. Filters conceptually include today, 7 days, 30 days, challenge lifetime, custom range, habit, and participant. Admin views add attention/risk, deadlines, debts, excuse requests, and payment requests.

## 8. Major Domain Entities

- **User:** authenticated person; identity is independent of challenge membership.
- **Challenge:** private accountability context with effective-dated timezone, lifecycle, and one currency (UZS by default).
- **Membership:** a user's participation state and effective dates in a challenge.
- **Role/Permission Assignment:** explicit administrative authority in a challenge.
- **Habit:** stable habit identity and recording type.
- **Habit Rule Version:** effective-dated schedule, target, penalty, and reminder terms.
- **Obligation:** one participant's required habit outcome for one period, bound to the applicable rule version.
- **Progress Event:** authoritative increment or duration recorded against an active obligation.
- **Completion/Correction Event:** server-recorded outcome or audited historical adjustment.
- **Ledger Transaction:** append-only challenge financial event such as penalty, confirmed payment, waiver, or adjustment.
- **Payment Request:** participant declaration tied to one user and challenge, reviewed by an authorized admin.
- **Excuse Request:** a participant's requested time range, reason, and selected habits, with an audited admin decision.
- **Activity Event:** challenge-visible event suitable for an in-app feed.
- **Notification Preference/Delivery:** per-category choice and resulting in-app/push delivery record.
- **Audit Event:** immutable record of sensitive administrative action.

These are conceptual entities, not a database schema.

## 9. MVP Boundary

The MVP includes one Flutter app, temporary-password provisioned access, one full challenge-level admin role assignable to multiple users, challenge/membership administration, supported habit types, manual duration progress, effective-dated rules/timezones, server-authoritative completion, partial quantity progress, independent selective excuse review, daily discipline streaks, penalties and derived debt, payment approval, fair ranking, essential statistics, realtime in-app activity, FCM notifications, preferences, and audit history for sensitive changes.

MVP payment handling is declaration plus admin confirmation only. Authoritative completion requires successful server receipt by the deadline; offline drafts may improve UX later but cannot establish completion.

## 10. Future / V2 Candidates

- Digest controls for high-volume team activity
- Cross-challenge aggregate finance dashboard (read-only aggregation)
- Richer analytics and export
- Additional administrative permission granularity
- Trusted-reviewer or delegated-review workflows for challenges that cannot add a second admin
- Wearable/health integrations
- Carefully designed offline progress drafts that still obey server deadlines
- More notification scheduling controls

## 11. Success Criteria

- Participants can identify what is due and how much progress remains without ambiguity.
- Changing device time cannot extend a window or improve rank.
- Historical obligations reproduce the rule effective when they were created.
- A missed obligation deterministically produces the correct status and penalty.
- An approved excuse preserves “not completed” history, prevents or compensates its penalty, and is reported separately from completions.
- Debt equals the sum of challenge ledger effects; payment requests alone never alter it.
- Rankings always favor better completion performance before timing.
- Admin corrections and financial decisions identify actor, time, reason/outcome, and prior state.
- No admin can review their own excuse, and no historical correction receives on-time ranking treatment without pre-existing authoritative evidence.
- App-open activity feels timely; background alerts use push delivery without spam.
- Core flows handle loading, empty, error, permission-denied, and offline states explicitly.

## 12. Risks and Assumptions

- Incorrect period/timezone handling could corrupt deadlines, penalties, and ranking history.
- Concurrent progress, deadline evaluation, payment review, or correction can double-apply effects without idempotency and constraints.
- Notification permission denial may reduce reminder effectiveness; in-app state remains authoritative.
- Financial terminology must not imply real payment processing.
- Admin/participant dual roles increase the risk of UI-based authorization assumptions.
- A sole admin's excuse request may remain pending until another admin is added, which can delay resolution.
- The MVP assumes reliable connectivity is required for authoritative completion.

## 13. Open Questions

None currently.

## 14. Glossary

- **Challenge:** Private team program containing members, habits, rules, and accountability history.
- **Sardor:** Team leader/admin; may separately be a participant.
- **Habit:** Repeated behavior being tracked.
- **Habit rule version:** Terms effective for a defined interval without rewriting prior terms.
- **Period:** Daily or weekly interval in the challenge timezone.
- **Obligation:** A participant's expected result for a habit period.
- **Eligible obligation:** An obligation included in completion and ranking calculations.
- **Excused miss:** A covered obligation that was not completed but has an approved justification; it is visible, non-successful, non-penalized, and neutral in completion rate and streak calculations.
- **Eligible weekly target:** Original weekly target minus explicitly approved excused units.
- **Deadline:** Server-evaluated end of the completion window.
- **Normalized completion time:** Fraction of the available window elapsed when completion occurred.
- **Debt:** Derived outstanding financial amount for a user in one challenge.
- **Ledger:** Append-only source of truth for penalties, payments, waivers, and adjustments.
- **Payment request:** Non-monetary declaration awaiting admin review.
