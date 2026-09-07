begin;

set local search_path = pg_catalog, public;

create type public.task_outcome_status as enum (
  'PENDING',
  'COMPLETED_ON_TIME',
  'MISSED',
  'COMPLETED_LATE',
  'EXCUSED'
);

create type public.task_progress_event_kind as enum (
  'PROGRESS_ADDED',
  'COMPLETION_RECORDED',
  'OCCURRENCE_RECORDED',
  'COMPLETION_REVOKED'
);

comment on type public.task_outcome_status is
  'Effective task outcome. EXCUSED is an accountable non-completion, never fabricated completion truth.';
comment on type public.task_progress_event_kind is
  'Append-only participant evidence kinds. PROGRESS_ADDED is a positive delta; revocation references and invalidates one prior positive event.';

-- These forward-safe keys let task foreign keys prove that membership and the
-- exact rule version belong to the same challenge/habit without rewriting 0002
-- or 0003. Their UUID ids remain globally unique primary keys.
alter table public.challenge_members
  add constraint challenge_members_challenge_id_id_key
  unique (challenge_id, id);

alter table public.habit_rule_versions
  add constraint habit_rule_versions_challenge_habit_id_id_key
  unique (challenge_id, habit_id, id);

create table public.task_instances (
  id uuid primary key default gen_random_uuid(),
  challenge_id uuid not null
    references public.challenges (id) on update restrict on delete restrict,
  challenge_member_id uuid not null,
  habit_id uuid not null,
  habit_rule_version_id uuid not null,
  period_kind public.period_kind not null,
  period_start_date date not null,
  period_end_date date not null,
  timezone_name text not null,
  opens_at timestamptz not null,
  deadline_at timestamptz not null,
  habit_type public.habit_type not null,
  original_target numeric not null,
  unit text,
  penalty_mode public.penalty_mode not null,
  penalty_amount numeric(18, 2) not null,
  current_progress numeric not null default 0,
  was_completed boolean not null default false,
  outcome_status public.task_outcome_status not null default 'PENDING',
  authoritative_completed_at timestamptz,
  effective_participant_completion_event_id uuid,
  created_at timestamptz not null default statement_timestamp(),
  updated_at timestamptz not null default statement_timestamp(),

  constraint task_instances_member_scope_fkey
    foreign key (challenge_id, challenge_member_id)
    references public.challenge_members (challenge_id, id)
    on update restrict on delete restrict,
  constraint task_instances_habit_scope_fkey
    foreign key (challenge_id, habit_id)
    references public.habits (challenge_id, id)
    on update restrict on delete restrict,
  constraint task_instances_rule_scope_fkey
    foreign key (challenge_id, habit_id, habit_rule_version_id)
    references public.habit_rule_versions (challenge_id, habit_id, id)
    on update restrict on delete restrict,
  constraint task_instances_obligation_key
    unique (
      challenge_member_id,
      habit_id,
      period_kind,
      period_start_date
    ),
  constraint task_instances_valid_period_dates
    check (
      (
        period_kind = 'DAILY'
        and period_end_date = period_start_date
      )
      or
      (
        period_kind = 'WEEKLY'
        and extract(isodow from period_start_date) = 1
        and period_end_date = period_start_date + 6
      )
    ),
  constraint task_instances_timezone_name_not_blank
    check (btrim(timezone_name) <> ''),
  constraint task_instances_timezone_name_is_trimmed
    check (timezone_name = btrim(timezone_name)),
  constraint task_instances_valid_window
    check (deadline_at > opens_at),
  constraint task_instances_positive_original_target
    check (original_target > 0),
  constraint task_instances_unit_not_blank
    check (unit is null or btrim(unit) <> ''),
  constraint task_instances_penalty_nonnegative
    check (penalty_amount >= 0),
  constraint task_instances_penalty_mode_matches_period
    check (
      (period_kind = 'DAILY' and penalty_mode = 'FIXED')
      or
      (
        period_kind = 'WEEKLY'
        and penalty_mode in ('PER_MISSING_UNIT', 'FIXED_IF_TARGET_MISSED')
      )
    ),
  constraint task_instances_progress_nonnegative
    check (current_progress >= 0),
  constraint task_instances_outcome_fact_consistency
    check (
      (
        outcome_status = 'COMPLETED_ON_TIME'
        and was_completed
        and authoritative_completed_at is not null
        and authoritative_completed_at >= opens_at
        and authoritative_completed_at <= deadline_at
      )
      or
      (
        outcome_status = 'COMPLETED_LATE'
        and was_completed
        and effective_participant_completion_event_id is null
        and (
          authoritative_completed_at is null
          or authoritative_completed_at > deadline_at
        )
      )
      or
      (
        outcome_status in ('PENDING', 'MISSED', 'EXCUSED')
        and not was_completed
        and authoritative_completed_at is null
        and effective_participant_completion_event_id is null
      )
    ),
  constraint task_instances_effective_pointer_outcome
    check (
      effective_participant_completion_event_id is null
      or outcome_status = 'COMPLETED_ON_TIME'
    )
);

comment on table public.task_instances is
  'Concrete challenge/member obligation with frozen period, rule, timezone, target, and penalty truth plus rebuildable effective projections.';
comment on column public.task_instances.habit_rule_version_id is
  'Exact immutable rule-version source used when this obligation was materialized.';
comment on column public.task_instances.timezone_name is
  'Frozen challenge IANA timezone name used to derive the local period and authoritative UTC window.';
comment on column public.task_instances.original_target is
  'Frozen positive target; boolean and occurrence materialization use an explicit target such as 1.';
comment on column public.task_instances.current_progress is
  'Server-maintained cache rebuildable by summing unreversed positive progress events and applying later privileged decisions.';
comment on column public.task_instances.authoritative_completed_at is
  'Current valid server completion evidence time; exact deadline is on time. Null for uncompleted and evidence-less late acknowledgements.';
comment on column public.task_instances.effective_participant_completion_event_id is
  'Nullable cache of the current normal participant event that establishes on-time completion; never the sole historical evidence.';
comment on constraint task_instances_obligation_key
  on public.task_instances is
  'Makes materialization idempotent for one member, habit, cadence, and local period start.';

create index task_instances_participant_today_idx
  on public.task_instances (
    challenge_member_id,
    outcome_status,
    opens_at,
    deadline_at
  );

create index task_instances_participant_history_idx
  on public.task_instances (challenge_member_id, period_start_date desc);

create index task_instances_admin_monitor_idx
  on public.task_instances (
    challenge_id,
    period_start_date,
    outcome_status,
    deadline_at
  );

create index task_instances_missed_idx
  on public.task_instances (challenge_id, outcome_status, deadline_at)
  where outcome_status = 'MISSED';

create index task_instances_ranking_idx
  on public.task_instances (challenge_id, deadline_at, outcome_status);

create index task_instances_due_pending_idx
  on public.task_instances (deadline_at, id)
  where outcome_status = 'PENDING';

create index task_instances_habit_rule_version_idx
  on public.task_instances (habit_rule_version_id);

create index task_instances_effective_completion_event_idx
  on public.task_instances (effective_participant_completion_event_id)
  where effective_participant_completion_event_id is not null;

create table public.task_progress_events (
  id uuid primary key default gen_random_uuid(),
  task_instance_id uuid not null
    references public.task_instances (id) on update restrict on delete restrict,
  actor_id uuid not null
    references public.profiles (id) on update restrict on delete restrict,
  event_kind public.task_progress_event_kind not null,
  amount numeric not null,
  occurrence_local_date date,
  accepted_at timestamptz not null default statement_timestamp(),
  reverses_event_id uuid,
  request_id uuid not null,
  metadata jsonb,

  constraint task_progress_events_request_id_key
    unique (request_id),
  constraint task_progress_events_task_id_id_key
    unique (task_instance_id, id),
  constraint task_progress_events_task_actor_id_key
    unique (task_instance_id, actor_id, id),
  constraint task_progress_events_reversal_target_fkey
    foreign key (task_instance_id, actor_id, reverses_event_id)
    references public.task_progress_events (task_instance_id, actor_id, id)
    on update restrict on delete restrict,
  constraint task_progress_events_valid_shape
    check (
      (
        event_kind in ('PROGRESS_ADDED', 'COMPLETION_RECORDED')
        and amount > 0
        and occurrence_local_date is null
        and reverses_event_id is null
      )
      or
      (
        event_kind = 'OCCURRENCE_RECORDED'
        and amount > 0
        and occurrence_local_date is not null
        and reverses_event_id is null
      )
      or
      (
        event_kind = 'COMPLETION_REVOKED'
        and amount = 0
        and occurrence_local_date is null
        and reverses_event_id is not null
      )
    ),
  constraint task_progress_events_metadata_is_object
    check (metadata is null or jsonb_typeof(metadata) = 'object')
);

-- The partial unique index both prevents repeated reversal of one source event
-- and serves targeted reversal lookups without indexing nulls.
create unique index task_progress_events_reverses_event_id_key
  on public.task_progress_events (reverses_event_id)
  where reverses_event_id is not null;

create index task_progress_events_task_chronological_idx
  on public.task_progress_events (task_instance_id, accepted_at);

create index task_progress_events_actor_chronological_idx
  on public.task_progress_events (actor_id, accepted_at desc);

create index task_progress_events_occurrence_local_day_idx
  on public.task_progress_events (
    task_instance_id,
    occurrence_local_date,
    accepted_at
  )
  where event_kind = 'OCCURRENCE_RECORDED';

comment on table public.task_progress_events is
  'Immutable server-accepted participant progress, completion, occurrence, and linked revocation evidence.';
comment on column public.task_progress_events.amount is
  'Positive delta for normal evidence and exactly zero for COMPLETION_REVOKED.';
comment on column public.task_progress_events.occurrence_local_date is
  'Server-derived challenge-local calendar date, present only for counted occurrence events.';
comment on column public.task_progress_events.accepted_at is
  'Authoritative database acceptance time; clients receive no direct insert path.';
comment on column public.task_progress_events.reverses_event_id is
  'Prior same-task, same-actor positive event invalidated by this append-only revocation.';
comment on column public.task_progress_events.request_id is
  'Globally unique idempotency key for progress, completion, occurrence, and revocation requests.';
comment on column public.task_progress_events.metadata is
  'Optional sanitized object metadata; never authoritative for actor, timing, scope, progress, or outcome.';
comment on constraint task_progress_events_reversal_target_fkey
  on public.task_progress_events is
  'Structurally prevents a revocation from targeting another task or actor. Migration 0009 validates source kind, current effectiveness, and weekly LIFO semantics under the task lock.';

-- Add the task-to-event side only after both tables exist. The composite key
-- ensures a cached completion pointer can never reference another task.
alter table public.task_instances
  add constraint task_instances_effective_completion_event_fkey
  foreign key (id, effective_participant_completion_event_id)
  references public.task_progress_events (task_instance_id, id)
  on update restrict on delete restrict;

-- Event evidence is append-only even for privileged database paths. Future
-- controlled operations append rows and update only the rebuildable task cache.
create function public.prevent_task_progress_event_mutation()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
  raise exception using
    errcode = '55000',
    message = 'task_progress_events are append-only';

  return old;
end;
$$;

revoke all on function public.prevent_task_progress_event_mutation()
  from public, anon, authenticated;

create trigger task_progress_events_prevent_mutation
before update or delete
on public.task_progress_events
for each row
execute function public.prevent_task_progress_event_mutation();

comment on function public.prevent_task_progress_event_mutation() is
  'Invoker-rights trigger helper enforcing immutable task progress evidence; it implements no business transition.';

alter table public.task_instances enable row level security;
alter table public.task_progress_events enable row level security;

-- Intentional deny-by-default foundation. Migration 0008 adds deliberate read
-- policies and grants; migration 0009 adds the only participant mutation RPCs.
revoke all on table public.task_instances from public, anon, authenticated;
revoke all on table public.task_progress_events from public, anon, authenticated;

commit;
