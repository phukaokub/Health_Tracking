-- Step 4 local foundation. Canonical values and provenance only; no raw JSON,
-- paths, device identifiers, ECG/RRI samples, or GPS route data are retained.
create table public.health_samples (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  import_id uuid not null,
  import_file_id uuid not null,
  dedupe_key text not null,
  source_family text not null,
  source_type text not null,
  source_record_hash text not null,
  started_at timestamptz not null,
  ended_at timestamptz not null,
  unit text not null,
  value numeric not null,
  parser_version text not null,
  created_at timestamptz not null default now(),
  constraint health_samples_import_owner_fk foreign key (import_id, user_id) references public.import_runs(id, user_id) on delete cascade,
  constraint health_samples_file_owner_fk foreign key (import_file_id, import_id, user_id) references public.import_files(id, import_id, user_id) on delete cascade,
  constraint health_samples_dedupe_format check (dedupe_key ~ '^[0-9a-f]{64}$'),
  constraint health_samples_source_record_hash_format check (source_record_hash ~ '^[0-9a-f]{64}$'),
  constraint health_samples_time_bounds check (ended_at >= started_at),
  constraint health_samples_family_length check (char_length(source_family) between 1 and 64),
  constraint health_samples_type_length check (char_length(source_type) between 1 and 64),
  constraint health_samples_unit_check check (unit in ('bpm', 'count', 'metres', 'seconds')),
  constraint health_samples_parser_version_length check (char_length(parser_version) between 1 and 64),
  constraint health_samples_owner_dedupe_key unique (user_id, dedupe_key)
);

create table public.normalization_provenance (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  import_id uuid not null,
  import_file_id uuid not null,
  source_family text not null,
  source_record_hash text not null,
  parser_version text not null,
  unit_conversion_version text not null default 'v1',
  timezone_resolution text not null,
  warning_code text,
  created_at timestamptz not null default now(),
  constraint normalization_provenance_import_owner_fk foreign key (import_id, user_id) references public.import_runs(id, user_id) on delete cascade,
  constraint normalization_provenance_file_owner_fk foreign key (import_file_id, import_id, user_id) references public.import_files(id, import_id, user_id) on delete cascade,
  constraint normalization_provenance_source_hash_format check (source_record_hash ~ '^[0-9a-f]{64}$'),
  constraint normalization_provenance_timezone_resolution check (timezone_resolution in ('explicit_offset', 'profile_fallback')),
  constraint normalization_provenance_warning_code check (warning_code is null or warning_code ~ '^[a-z0-9_]{3,80}$')
);

create index health_samples_owner_time_idx on public.health_samples (user_id, started_at desc);
create index normalization_provenance_owner_import_idx on public.normalization_provenance (user_id, import_id, created_at desc);

alter table public.health_samples enable row level security;
alter table public.normalization_provenance enable row level security;

grant select on public.health_samples to authenticated;
grant select on public.normalization_provenance to authenticated;

create policy "Health samples are readable by owner" on public.health_samples
  for select to authenticated using ((select auth.uid()) = user_id);
create policy "Normalization provenance is readable by owner" on public.normalization_provenance
  for select to authenticated using ((select auth.uid()) = user_id);
