begin;

-- Migration 0001 installed btree_gist. Keep its UUID operator classes visible
-- for the temporal exclusion constraints without reinstalling the extension.
set local search_path = pg_catalog, public, extensions;

create type public.challenge_member_status as enum (
  'ACTIVE',
  'INACTIVE',
  'REMOVED'
);

create table public.challenge_members (
  id uuid primary key default gen_random_uuid(),
  challenge_id uuid not null
    references public.challenges (id) on update restrict on delete restrict,
  user_id uuid not null
    references public.profiles (id) on update restrict on delete restrict,
  status public.challenge_member_status not null default 'ACTIVE',
  joined_at timestamptz not null default statement_timestamp(),
  ended_at timestamptz,
  status_reason text,
  created_at timestamptz not null default statement_timestamp(),
  updated_at timestamptz not null default statement_timestamp(),

  constraint challenge_members_valid_interval
    check (ended_at is null or ended_at >= joined_at),
  constraint challenge_members_status_matches_interval
    check (
      (status = 'ACTIVE' and ended_at is null)
      or
      (status in ('INACTIVE', 'REMOVED') and ended_at is not null)
    ),
  constraint challenge_members_no_overlapping_periods
    exclude using gist (
      challenge_id with =,
      user_id with =,
      tstzrange(joined_at, ended_at, '[)') with &&
    )
);

create index challenge_members_user_status_idx
  on public.challenge_members (user_id, status);

create index challenge_members_challenge_status_idx
  on public.challenge_members (challenge_id, status);

create index challenge_members_challenge_period_idx
  on public.challenge_members (challenge_id, joined_at, ended_at);

create index challenge_members_active_lookup_idx
  on public.challenge_members (challenge_id, user_id)
  where status = 'ACTIVE';

comment on table public.challenge_members is
  'Append-oriented challenge participation periods, independent from administrative authority.';
comment on column public.challenge_members.status_reason is
  'Reason recorded by the future audited membership transition workflow.';
comment on constraint challenge_members_no_overlapping_periods
  on public.challenge_members is
  'Prevents overlapping historical periods and therefore more than one open active membership per challenge/user.';

create table public.challenge_admins (
  id uuid primary key default gen_random_uuid(),
  challenge_id uuid not null
    references public.challenges (id) on update restrict on delete restrict,
  user_id uuid not null
    references public.profiles (id) on update restrict on delete restrict,
  granted_at timestamptz not null default statement_timestamp(),
  revoked_at timestamptz,
  granted_by uuid not null
    references public.profiles (id) on update restrict on delete restrict,
  created_at timestamptz not null default statement_timestamp(),

  constraint challenge_admins_valid_interval
    check (revoked_at is null or revoked_at > granted_at),
  constraint challenge_admins_no_overlapping_grants
    exclude using gist (
      challenge_id with =,
      user_id with =,
      tstzrange(granted_at, revoked_at, '[)') with &&
    )
);

create index challenge_admins_user_challenge_active_idx
  on public.challenge_admins (user_id, challenge_id)
  where revoked_at is null;

create index challenge_admins_challenge_active_idx
  on public.challenge_admins (challenge_id)
  where revoked_at is null;

comment on table public.challenge_admins is
  'Append-oriented challenge-scoped admin grants, independent from participation.';
comment on constraint challenge_admins_no_overlapping_grants
  on public.challenge_admins is
  'Prevents overlapping historical grants and therefore more than one open admin grant per challenge/user.';

create table public.challenge_pauses (
  id uuid primary key default gen_random_uuid(),
  challenge_id uuid not null
    references public.challenges (id) on update restrict on delete restrict,
  starts_at timestamptz not null default statement_timestamp(),
  ends_at timestamptz,
  reason text not null,
  created_by uuid not null
    references public.profiles (id) on update restrict on delete restrict,
  ended_by uuid
    references public.profiles (id) on update restrict on delete restrict,
  created_at timestamptz not null default statement_timestamp(),
  updated_at timestamptz not null default statement_timestamp(),
  request_id uuid not null,

  constraint challenge_pauses_valid_interval
    check (ends_at is null or ends_at > starts_at),
  constraint challenge_pauses_end_actor_consistency
    check (
      (ends_at is null and ended_by is null)
      or
      (ends_at is not null and ended_by is not null)
    ),
  constraint challenge_pauses_reason_not_blank
    check (btrim(reason) <> ''),
  constraint challenge_pauses_request_id_key
    unique (request_id),
  constraint challenge_pauses_no_overlap
    exclude using gist (
      challenge_id with =,
      tstzrange(starts_at, ends_at, '[)') with &&
    )
);

create index challenge_pauses_challenge_starts_at_idx
  on public.challenge_pauses (challenge_id, starts_at desc);

create index challenge_pauses_open_challenge_idx
  on public.challenge_pauses (challenge_id)
  where ends_at is null;

comment on table public.challenge_pauses is
  'Append-oriented challenge pause intervals; later RPCs apply neutral task effects transactionally.';
comment on column public.challenge_pauses.ended_by is
  'Set by the future audited resume workflow; no client write path exists in migration 0002.';

alter table public.challenge_members enable row level security;
alter table public.challenge_admins enable row level security;
alter table public.challenge_pauses enable row level security;

-- Intentional deny-by-default foundation. Migration 0008 adds deliberate read
-- policies and the table grants they require; migration 0012 adds mutation RPCs.
revoke all on table public.challenge_members from public, anon, authenticated;
revoke all on table public.challenge_admins from public, anon, authenticated;
revoke all on table public.challenge_pauses from public, anon, authenticated;

-- The two creator-FK indexes suggested after migration 0001 remain deferred to
-- migration 0015 because current documented queries do not use those columns.

commit;
