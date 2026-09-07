begin;

-- Required by the UUID + timestamptz range exclusion constraint below.
-- Supabase provides the extensions schema; no other extension is introduced here.
create extension if not exists btree_gist with schema extensions;

-- Keep extension-provided operator classes visible while all application objects
-- remain explicitly schema-qualified.
set local search_path = pg_catalog, public, extensions;

create type public.challenge_status as enum (
  'DRAFT',
  'ACTIVE',
  'PAUSED',
  'ENDED'
);

create table public.profiles (
  id uuid primary key
    references auth.users (id) on update restrict on delete restrict,
  display_name text not null,
  username text,
  must_change_password boolean not null default true,
  created_at timestamptz not null default statement_timestamp(),
  updated_at timestamptz not null default statement_timestamp(),

  constraint profiles_display_name_not_blank
    check (btrim(display_name) <> ''),
  constraint profiles_username_not_blank
    check (username is null or btrim(username) <> ''),
  constraint profiles_username_is_trimmed
    check (username is null or username = btrim(username))
);

create unique index profiles_username_case_insensitive_key
  on public.profiles (lower(username))
  where username is not null;

comment on table public.profiles is
  'Application identity linked one-to-one to auth.users; never stores passwords.';
comment on column public.profiles.must_change_password is
  'Provisioning state controlled by a future private Auth/profile workflow.';
comment on column public.profiles.updated_at is
  'Set by future controlled profile mutations; no generic update trigger exists in migration 0001.';

create table public.challenges (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  description text,
  status public.challenge_status not null default 'DRAFT',
  start_date date not null,
  end_date date,
  currency_code char(3) not null default 'UZS',
  created_by uuid not null
    references public.profiles (id) on update restrict on delete restrict,
  created_at timestamptz not null default statement_timestamp(),
  updated_at timestamptz not null default statement_timestamp(),

  constraint challenges_name_not_blank
    check (btrim(name) <> ''),
  constraint challenges_valid_date_range
    check (end_date is null or end_date >= start_date),
  constraint challenges_currency_code_format
    check (currency_code::text ~ '^[A-Z]{3}$')
);

create index challenges_status_start_date_idx
  on public.challenges (status, start_date);

comment on table public.challenges is
  'Stable challenge identity and current lifecycle projection.';
comment on column public.challenges.currency_code is
  'ISO 4217 representation. Immutability after the first ledger entry is enforced in migration 0006.';
comment on column public.challenges.updated_at is
  'Set by future controlled challenge mutations; no generic update trigger exists in migration 0001.';

create table public.challenge_timezone_versions (
  id uuid primary key default gen_random_uuid(),
  challenge_id uuid not null
    references public.challenges (id) on update restrict on delete restrict,
  timezone_name text not null,
  effective_from timestamptz not null,
  effective_to timestamptz,
  created_by uuid not null
    references public.profiles (id) on update restrict on delete restrict,
  created_at timestamptz not null default statement_timestamp(),
  request_id uuid not null,

  constraint challenge_timezone_versions_timezone_name_not_blank
    check (btrim(timezone_name) <> ''),
  constraint challenge_timezone_versions_timezone_name_is_trimmed
    check (timezone_name = btrim(timezone_name)),
  constraint challenge_timezone_versions_valid_interval
    check (effective_to is null or effective_to > effective_from),
  constraint challenge_timezone_versions_challenge_effective_from_key
    unique (challenge_id, effective_from),
  constraint challenge_timezone_versions_request_id_key
    unique (request_id),
  constraint challenge_timezone_versions_no_overlap
    exclude using gist (
      challenge_id with =,
      tstzrange(effective_from, effective_to, '[)') with &&
    )
);

-- PostgreSQL's timezone catalog is the authority for names accepted by AT TIME ZONE.
-- A trigger is necessary because CHECK constraints cannot contain the catalog lookup.
create function public.validate_challenge_timezone_name()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
  if not exists (
    select 1
    from pg_catalog.pg_timezone_names as timezone_catalog
    where timezone_catalog.name = new.timezone_name
  ) then
    raise exception using
      errcode = '22023',
      message = pg_catalog.format(
        'unrecognized IANA timezone name: %s',
        new.timezone_name
      );
  end if;

  return new;
end;
$$;

revoke all on function public.validate_challenge_timezone_name() from public;
revoke all on function public.validate_challenge_timezone_name() from anon, authenticated;

create trigger challenge_timezone_versions_validate_timezone_name
before insert or update of timezone_name
on public.challenge_timezone_versions
for each row
execute function public.validate_challenge_timezone_name();

comment on table public.challenge_timezone_versions is
  'Append-oriented IANA timezone history using non-overlapping [effective_from, effective_to) ranges.';
comment on column public.challenge_timezone_versions.effective_to is
  'A future timezone RPC may close the current range before appending its successor; historical ranges are not rewritten.';
comment on function public.validate_challenge_timezone_name() is
  'Invoker-rights trigger helper that validates names against pg_catalog.pg_timezone_names; not client executable.';

-- The unique constraint index also supports challenge-scoped latest-version lookups:
-- WHERE challenge_id = ? ORDER BY effective_from DESC LIMIT 1.

alter table public.profiles enable row level security;
alter table public.challenges enable row level security;
alter table public.challenge_timezone_versions enable row level security;

-- Intentional deny-by-default foundation: membership/admin scope does not exist yet,
-- so migration 0001 creates no client policies. Deliberate read policies arrive in 0008.
revoke all on table public.profiles from public, anon, authenticated;
revoke all on table public.challenges from public, anon, authenticated;
revoke all on table public.challenge_timezone_versions from public, anon, authenticated;

commit;
