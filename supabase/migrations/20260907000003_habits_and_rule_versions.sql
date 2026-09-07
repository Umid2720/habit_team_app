begin;

-- Migration 0001 installed btree_gist. Keep its UUID operator classes visible
-- for the effective-range exclusion constraint without reinstalling it.
set local search_path = pg_catalog, public, extensions;

create type public.habit_type as enum (
  'BOOLEAN',
  'QUANTITY',
  'DURATION',
  'DAILY_OCCURRENCE',
  'WEEKLY_TARGET'
);

create type public.period_kind as enum (
  'DAILY',
  'WEEKLY'
);

create type public.penalty_mode as enum (
  'FIXED',
  'PER_MISSING_UNIT',
  'FIXED_IF_TARGET_MISSED'
);

comment on type public.penalty_mode is
  'FIXED applies to daily obligations; MVP weekly rules use PER_MISSING_UNIT. FIXED_IF_TARGET_MISSED is reserved for documented future behavior.';

create table public.habits (
  id uuid primary key default gen_random_uuid(),
  challenge_id uuid not null
    references public.challenges (id) on update restrict on delete restrict,
  name text not null,
  description text,
  habit_type public.habit_type not null,
  is_active boolean not null default true,
  created_by uuid not null
    references public.profiles (id) on update restrict on delete restrict,
  created_at timestamptz not null default statement_timestamp(),
  updated_at timestamptz not null default statement_timestamp(),

  constraint habits_name_not_blank
    check (btrim(name) <> ''),
  constraint habits_challenge_id_id_key
    unique (challenge_id, id)
);

create index habits_challenge_active_idx
  on public.habits (challenge_id, is_active);

comment on table public.habits is
  'Stable challenge-owned habit identity; time-varying behavior belongs to habit_rule_versions.';
comment on column public.habits.habit_type is
  'Recording type. Migration 0012 must reject incompatible changes after task history exists.';
comment on column public.habits.is_active is
  'Logical availability for future periods; historical references must use restrictive foreign keys.';
comment on column public.habits.updated_at is
  'Set by future controlled habit mutations; no generic update trigger exists in migration 0003.';

create table public.habit_rule_versions (
  id uuid primary key default gen_random_uuid(),
  challenge_id uuid not null
    references public.challenges (id) on update restrict on delete restrict,
  habit_id uuid not null,
  effective_from timestamptz not null,
  effective_to timestamptz,
  period_kind public.period_kind not null,
  days_of_week smallint[] not null,
  target_value numeric,
  unit text,
  opens_local_time time without time zone not null,
  deadline_local_time time without time zone not null,
  penalty_mode public.penalty_mode not null,
  penalty_amount numeric(18, 2) not null default 0,
  reminder_start_local time without time zone,
  reminder_end_local time without time zone,
  reminder_interval_minutes integer,
  default_message_template text not null,
  admin_message_template text,
  created_by uuid not null
    references public.profiles (id) on update restrict on delete restrict,
  created_at timestamptz not null default statement_timestamp(),
  request_id uuid not null,

  constraint habit_rule_versions_habit_scope_fkey
    foreign key (challenge_id, habit_id)
    references public.habits (challenge_id, id)
    on update restrict on delete restrict,
  constraint habit_rule_versions_valid_interval
    check (effective_to is null or effective_to > effective_from),
  constraint habit_rule_versions_valid_days_of_week
    check (
      cardinality(days_of_week) > 0
      and array_position(days_of_week, null) is null
      and days_of_week <@ array[1, 2, 3, 4, 5, 6, 7]::smallint[]
    ),
  constraint habit_rule_versions_positive_target
    check (target_value is null or target_value > 0),
  constraint habit_rule_versions_weekly_target_required
    check (
      period_kind <> 'WEEKLY'
      or (target_value is not null and target_value > 0)
    ),
  constraint habit_rule_versions_unit_not_blank
    check (unit is null or btrim(unit) <> ''),
  constraint habit_rule_versions_valid_daily_window
    check (
      period_kind <> 'DAILY'
      or deadline_local_time > opens_local_time
    ),
  constraint habit_rule_versions_penalty_mode_matches_period
    check (
      (period_kind = 'DAILY' and penalty_mode = 'FIXED')
      or
      (
        period_kind = 'WEEKLY'
        and penalty_mode in ('PER_MISSING_UNIT', 'FIXED_IF_TARGET_MISSED')
      )
    ),
  constraint habit_rule_versions_penalty_nonnegative
    check (penalty_amount >= 0),
  constraint habit_rule_versions_reminder_fields_complete
    check (
      (
        reminder_start_local is null
        and reminder_end_local is null
        and reminder_interval_minutes is null
      )
      or
      (
        reminder_start_local is not null
        and reminder_end_local is not null
        and reminder_interval_minutes is not null
      )
    ),
  constraint habit_rule_versions_valid_reminder_range
    check (
      reminder_start_local is null
      or reminder_end_local > reminder_start_local
    ),
  constraint habit_rule_versions_positive_reminder_interval
    check (
      reminder_interval_minutes is null
      or reminder_interval_minutes > 0
    ),
  constraint habit_rule_versions_daily_reminder_within_window
    check (
      period_kind <> 'DAILY'
      or reminder_start_local is null
      or (
        reminder_start_local >= opens_local_time
        and reminder_end_local <= deadline_local_time
      )
    ),
  constraint habit_rule_versions_default_message_not_blank
    check (btrim(default_message_template) <> ''),
  constraint habit_rule_versions_admin_message_not_blank
    check (
      admin_message_template is null
      or btrim(admin_message_template) <> ''
    ),
  constraint habit_rule_versions_habit_effective_from_key
    unique (habit_id, effective_from),
  constraint habit_rule_versions_request_id_key
    unique (request_id),
  constraint habit_rule_versions_no_overlap
    exclude using gist (
      habit_id with =,
      tstzrange(effective_from, effective_to, '[)') with &&
    )
);

-- The unique (habit_id, effective_from) index supports latest-version lookup
-- with a backward scan; do not duplicate it solely to specify DESC.
create index habit_rule_versions_challenge_effective_idx
  on public.habit_rule_versions (
    challenge_id,
    effective_from,
    effective_to
  );

create index habit_rule_versions_challenge_habit_idx
  on public.habit_rule_versions (challenge_id, habit_id);

comment on table public.habit_rule_versions is
  'Effective-dated habit schedule, target, penalty, and reminder terms; tasks later bind to one exact version.';
comment on column public.habit_rule_versions.effective_to is
  'Exclusive end. Future versioning may close only an unused open range before appending its successor.';
comment on column public.habit_rule_versions.days_of_week is
  'ISO weekdays 1 through 7. Weekly period boundaries remain Monday through Sunday in the challenge timezone.';
comment on column public.habit_rule_versions.period_kind is
  'DAILY or WEEKLY cadence. Migration 0012 validates compatibility with the parent habit recording type.';
comment on column public.habit_rule_versions.target_value is
  'Positive when present. Exact habit-type compatibility is enforced by the future controlled rule RPC.';
comment on column public.habit_rule_versions.opens_local_time is
  'Challenge-local wall-clock time; future materialization freezes the corresponding authoritative UTC instant.';
comment on column public.habit_rule_versions.deadline_local_time is
  'Challenge-local wall-clock time; future materialization must prove the generated deadline follows opening.';
comment on column public.habit_rule_versions.penalty_amount is
  'Configured non-negative amount in the challenge currency; no financial history is created here.';
comment on column public.habit_rule_versions.default_message_template is
  'Versioned default reminder text; the future controlled creation flow supplies the product-localized default.';
comment on column public.habit_rule_versions.admin_message_template is
  'Optional admin-edited reminder template; the default template remains preserved on the rule version.';
comment on constraint habit_rule_versions_no_overlap
  on public.habit_rule_versions is
  'Prevents overlapping [effective_from, effective_to) versions while allowing adjacent versions.';

alter table public.habits enable row level security;
alter table public.habit_rule_versions enable row level security;

-- Intentional deny-by-default foundation. Migration 0008 adds deliberate read
-- policies and table grants; migration 0012 adds controlled habit/rule writes.
revoke all on table public.habits from public, anon, authenticated;
revoke all on table public.habit_rule_versions from public, anon, authenticated;

commit;
