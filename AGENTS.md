# Repository Guidelines

## Product and Priorities

Build a private team habit/accountability application for Android and iOS from one Flutter codebase. The same app serves participants and admins (`sardor`), and an admin may also participate in a challenge. Optimize, in order, for correctness, maintainability, security, premium UX, and efficient agent work. Prefer the simplest design that satisfies a current requirement; do not add speculative abstractions, packages, services, MCPs, or dependencies.

## Technology and Project Structure

- Client: Flutter with Riverpod and `go_router`.
- Backend: Supabase using PostgreSQL, Supabase Auth, Realtime, controlled RPC/functions, and Edge Functions where appropriate.
- Scheduled work: Supabase cron/`pg_cron` where appropriate.
- Background notifications: Firebase Cloud Messaging (FCM).

Application code belongs in `lib/`, tests in `test/`, and platform configuration in `android/` and `ios/`. As the app grows, organize `lib/` by feature and keep presentation, domain logic, and persistence separate where that separation adds clarity. Put reusable cross-feature code under a clearly named shared/core area. Never edit generated `build/` or `.dart_tool/` content manually.

## Domain and Time Invariants

The primary aggregate is a Challenge, containing participants, habits, rules, deadlines, penalties, and rankings. Habits may be daily or weekly and may use checkbox, quantity/counter, duration, daily-occurrence, or weekly-target semantics.

Habit targets, penalties, reminders, and other rules can change over time. Model them as versioned/effective-dated records. Never overwrite a historical rule in a way that changes old task results; stored history must remain reproducible.

Server time is authoritative. Never use device time or timezone to decide eligibility, deadlines, lateness, penalties, or rankings. Use explicit statuses such as `PENDING`, `COMPLETED_ON_TIME`, `MISSED`, `COMPLETED_LATE`, and `EXCUSED`; add statuses only for a demonstrated domain need.

Users may complete only their own currently eligible tasks and may not backdate them. The server generates completion timestamps. After a deadline, normal users cannot complete that period. An audited historical correction is `COMPLETED_ON_TIME` only when existing trusted server-side evidence proves completion by the deadline; otherwise an acknowledged completion is `COMPLETED_LATE`. Never fabricate completion time, and keep any penalty waiver separate from timing or ranking evidence. Protect important transitions with transactions, idempotency keys, and database constraints where possible.

## Penalties, Payments, and Ranking

Financial history is an append-only, challenge-scoped ledger. Current debt must be derived from that challenge's ledger transactions, not maintained as the sole source of truth. A future UI may aggregate debt across challenges, but authoritative approval and accounting remain challenge-scoped. Never silently delete or rewrite financial facts; waivers and corrections require explicit compensating records and audit history.

Hide the Pay action when debt is zero. A payment request must explicitly reference the challenge whose debt it pays. Accept it only when `0 < amount <= current outstanding debt`, with at most one `PENDING` request per user per challenge for the MVP. Submission notifies an admin but does not reduce debt. On approval, revalidate that challenge's debt on the server and atomically create the confirmed ledger entry, record reviewer/timestamps, and notify the user. Rejection does not affect debt. Financial writes must be transactional and idempotent.

Rank primarily by fulfilled eligible obligations/completion rate. Use completion timing only to break equal completion results; early completion never offsets a miss. When comparing different windows, prefer normalized timing: `(completed_at - opens_at) / (deadline_at - opens_at)`. Exclude excused, paused, and pre-join periods fairly. Rankings must be explainable and recomputable from preserved history.

## Notifications and Realtime

Support habit reminders, deadline warnings, team activity, penalties, admin payment-request alerts, and user payment decisions. Allow category preferences such as push plus in-app, in-app only, or disabled where product rules permit.

Reminder start, end, interval, and editable message template belong to the effective habit rule; provide a sensible default. Never send reminders after the applicable completion window. Use Supabase Realtime for app-open updates and FCM for app-closed/background delivery; a realtime subscription is not push delivery.

## Security and Audit

Treat the mobile client as untrusted. Enforce authorization and authoritative validation server-side with least-privilege RLS and controlled RPC/functions for sensitive mutations. Never expose service-role secrets to Flutter or store/log plaintext passwords. Admins may reset credentials but may never read passwords.

Challenge participation and administrative authorization are separate. A user may be both an admin/sardor and a ranked participant, but participation never grants management permissions. Administrative mutations require explicit server-side role/permission checks; never infer authorization from challenge participation. An admin must never approve or reject their own excuse request; a different admin must review it, and a sole admin's request remains `PENDING` until another admin is added. Ordinary participants cannot perform historical corrections, penalty waivers, payment approvals, membership management, or habit-rule management.

Maintain immutable audit history for admin task corrections, habit-rule changes, penalty changes or waivers, payment approvals/rejections, and important membership changes. Prefer appended facts over destructive updates.

## UI/UX Skill Routing and Direction

Use project-local skills deliberately:

1. `ui-ux-pro-max` decides mobile UX architecture, navigation, interaction structure, accessibility, touch targets, forms, and Flutter-specific patterns.
2. `tokens` and `design-system` establish reusable foundations.
3. `ui-craft` handles hierarchy, composition, premium visual execution, interaction quality, and critique.
4. `audit`, `critique`, `polish`, `harden`, and `finalize` review production quality.

Use `brief` for design briefs, `shape` before important new screens, `typeset` for typography, `animate`/`delight` for restrained micro-interactions, `adapt` for device layouts, `clarify` for UX copy, and `unhappy` for loading/offline/error states. Do not invoke unrelated skills such as `banner-design` or `slides` unless explicitly required.

Aim for a calm, serious, premium discipline product—not a generic checkbox tracker. Favor excellent typography, clear hierarchy, strong progress feedback, consistent spacing/components, tasteful celebration, restrained motion, and adaptable light/dark foundations. Avoid random gradients, excessive glassmorphism or emojis, decorative clutter, inconsistent cards, and generic AI-dashboard styling.

## Engineering, Testing, and Delivery

Use standard Dart formatting, two-space indentation, `lower_snake_case.dart` files, `UpperCamelCase` types, and `lowerCamelCase` members. Prefer strongly typed domain models, small scoped changes, existing components over duplicates, and explicit loading, empty, error, and offline behavior. Avoid silent failures and unrelated rewrites.

Useful commands:

- `flutter pub get` — resolve declared dependencies.
- `flutter run` — run on a connected device or emulator.
- `dart format lib test` — format project Dart files.
- `flutter analyze` — run analyzer and `flutter_lints`.
- `flutter test` — run unit and widget tests.

Name tests `*_test.dart`, mirror relevant source structure, and add regression coverage for fixes. Before declaring a Flutter implementation complete, run applicable formatting, analysis, and relevant tests; report changes, commands, failures/warnings, and assumptions. Never claim success after failed validation.

Use concise Conventional Commit-style subjects such as `feat: add challenge ranking` or `fix: reject stale payment approval`. Pull requests should explain motivation, link issues, describe validation, identify security/data implications, and include screenshots for UI changes.

## Agent Workflow and Documentation

Inspect narrowly, keep work small and verifiable, avoid unnecessary multi-agent workflows, and do not repeatedly rescan or regenerate satisfactory files. Preserve unrelated user changes. Keep concise durable invariants, engineering rules, quality gates, and pointers in `AGENTS.md`; put detailed behavior, edge cases, workflows, formulas, and schemas under `docs/`. Once detailed documents exist, do not duplicate their large specifications here. When a durable invariant changes, update both `AGENTS.md` and the relevant detailed document when applicable.
