-- Step 3 foundation: metadata only. Source file bytes are stored directly in the
-- private health-imports bucket; this schema never stores raw Huawei payloads or
-- user file paths.

create table public.import_runs (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  client_idempotency_key uuid not null,
  state text not null default 'draft',
  manifest_version smallint not null default 1,
  source_kind text not null,
  timezone_candidate text,
  total_file_count integer not null default 0,
  total_logical_bytes bigint not null default 0,
  cleanup_after timestamptz not null default (now() + interval '24 hours'),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint import_runs_owner_key unique (id, user_id),
  constraint import_runs_idempotency_key unique (user_id, client_idempotency_key),
  constraint import_runs_state_check check (state in (
    'draft', 'uploading', 'uploaded', 'queued', 'processing',
    'completed', 'completed_with_warnings', 'failed', 'cancelling',
    'cancelled', 'deleting', 'deleted'
  )),
  constraint import_runs_source_kind_check check (source_kind in ('directory', 'zip')),
  constraint import_runs_manifest_version_check check (manifest_version = 1),
  constraint import_runs_timezone_candidate_length check (
    timezone_candidate is null or char_length(timezone_candidate) between 1 and 64
  ),
  constraint import_runs_total_file_count_check check (total_file_count >= 0),
  constraint import_runs_total_logical_bytes_check check (total_logical_bytes >= 0)
);

create table public.import_manifest_pages (
  id uuid primary key default gen_random_uuid(),
  import_id uuid not null,
  user_id uuid not null,
  page_index integer not null,
  content_sha256 text not null,
  file_count integer not null,
  logical_bytes bigint not null,
  created_at timestamptz not null default now(),
  constraint import_manifest_pages_run_owner_fk
    foreign key (import_id, user_id)
    references public.import_runs (id, user_id) on delete cascade,
  constraint import_manifest_pages_index_key unique (import_id, page_index),
  constraint import_manifest_pages_content_key unique (import_id, content_sha256),
  constraint import_manifest_pages_page_index_check check (page_index >= 0),
  constraint import_manifest_pages_content_sha256_check check (content_sha256 ~ '^[0-9a-f]{64}$'),
  constraint import_manifest_pages_file_count_check check (file_count >= 0),
  constraint import_manifest_pages_logical_bytes_check check (logical_bytes >= 0)
);

create table public.import_files (
  id uuid primary key default gen_random_uuid(),
  import_id uuid not null,
  user_id uuid not null,
  client_file_id uuid not null,
  source_reference_hash text not null,
  source_family text not null,
  content_kind text not null,
  inclusion_state text not null default 'planned',
  logical_bytes bigint not null,
  content_sha256 text not null,
  duplicate_of_file_id uuid,
  parser_version_target text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint import_files_run_owner_fk
    foreign key (import_id, user_id)
    references public.import_runs (id, user_id) on delete cascade,
  constraint import_files_owner_key unique (id, import_id, user_id),
  constraint import_files_client_file_key unique (import_id, client_file_id),
  constraint import_files_source_reference_hash_check check (source_reference_hash ~ '^[0-9a-f]{64}$'),
  constraint import_files_content_sha256_check check (content_sha256 ~ '^[0-9a-f]{64}$'),
  constraint import_files_source_family_length check (char_length(source_family) between 1 and 64),
  constraint import_files_content_kind_length check (char_length(content_kind) between 1 and 128),
  constraint import_files_state_check check (inclusion_state in (
    'planned', 'uploading', 'uploaded', 'verified', 'failed',
    'skipped_duplicate', 'excluded', 'deleted'
  )),
  constraint import_files_logical_bytes_check check (logical_bytes >= 0)
);

create table public.import_file_parts (
  id uuid primary key default gen_random_uuid(),
  file_id uuid not null,
  import_id uuid not null,
  user_id uuid not null,
  part_index integer not null,
  byte_offset bigint not null,
  byte_length integer not null,
  content_sha256 text not null,
  object_path text not null,
  state text not null default 'planned',
  uploaded_at timestamptz,
  verified_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint import_file_parts_file_owner_fk
    foreign key (file_id, import_id, user_id)
    references public.import_files (id, import_id, user_id) on delete cascade,
  constraint import_file_parts_index_key unique (file_id, part_index),
  constraint import_file_parts_object_path_key unique (object_path),
  constraint import_file_parts_content_sha256_check check (content_sha256 ~ '^[0-9a-f]{64}$'),
  constraint import_file_parts_index_check check (part_index >= 0),
  constraint import_file_parts_offset_check check (byte_offset >= 0),
  constraint import_file_parts_length_check check (byte_length between 1 and 20971520),
  constraint import_file_parts_object_path_check check (
    object_path ~ '^imports/[0-9a-f-]{36}/[0-9a-f-]{36}/[0-9a-f-]{36}/part-[0-9]+$'
  ),
  constraint import_file_parts_state_check check (state in (
    'planned', 'uploading', 'uploaded', 'verified', 'failed', 'deleted'
  ))
);

create table public.import_jobs (
  id uuid primary key default gen_random_uuid(),
  import_id uuid not null,
  user_id uuid not null,
  job_type text not null default 'parse_import',
  state text not null default 'queued',
  attempt_count integer not null default 0,
  lease_expires_at timestamptz,
  parser_version text,
  checkpoint jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint import_jobs_run_owner_fk
    foreign key (import_id, user_id)
    references public.import_runs (id, user_id) on delete cascade,
  constraint import_jobs_initial_job_key unique (import_id, job_type),
  constraint import_jobs_type_check check (job_type = 'parse_import'),
  constraint import_jobs_state_check check (state in (
    'queued', 'leased', 'processing', 'completed', 'failed', 'cancelled'
  )),
  constraint import_jobs_attempt_count_check check (attempt_count >= 0)
);

create table public.import_errors (
  id uuid primary key default gen_random_uuid(),
  import_id uuid not null,
  user_id uuid not null,
  code text not null,
  retryable boolean not null default false,
  safe_detail text,
  occurrence_count integer not null default 1,
  first_occurred_at timestamptz not null default now(),
  last_occurred_at timestamptz not null default now(),
  resolved_at timestamptz,
  constraint import_errors_run_owner_fk
    foreign key (import_id, user_id)
    references public.import_runs (id, user_id) on delete cascade,
  constraint import_errors_code_format check (code ~ '^[a-z0-9_]{3,80}$'),
  constraint import_errors_safe_detail_length check (
    safe_detail is null or char_length(safe_detail) <= 500
  ),
  constraint import_errors_occurrence_count_check check (occurrence_count >= 1)
);

create index import_runs_user_state_created_at_idx
  on public.import_runs (user_id, state, created_at desc);
create index import_manifest_pages_import_id_idx
  on public.import_manifest_pages (import_id, page_index);
create index import_files_user_import_id_idx
  on public.import_files (user_id, import_id);
create index import_file_parts_user_import_id_idx
  on public.import_file_parts (user_id, import_id);
create index import_jobs_user_state_created_at_idx
  on public.import_jobs (user_id, state, created_at);
create index import_errors_user_import_id_idx
  on public.import_errors (user_id, import_id, last_occurred_at desc);

alter table public.import_runs enable row level security;
alter table public.import_manifest_pages enable row level security;
alter table public.import_files enable row level security;
alter table public.import_file_parts enable row level security;
alter table public.import_jobs enable row level security;
alter table public.import_errors enable row level security;

grant select, insert, update, delete on table public.import_runs to authenticated;
grant select, insert, update, delete on table public.import_manifest_pages to authenticated;
grant select, insert, update, delete on table public.import_files to authenticated;
grant select, insert, update, delete on table public.import_file_parts to authenticated;
grant select, insert, update, delete on table public.import_jobs to authenticated;
grant select, insert, update, delete on table public.import_errors to authenticated;

create policy "Import runs are readable by owner"
  on public.import_runs for select using ((select auth.uid()) = user_id);
create policy "Import runs are insertable by owner"
  on public.import_runs for insert with check ((select auth.uid()) = user_id);
create policy "Import runs are updateable by owner"
  on public.import_runs for update
  using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);
create policy "Import runs are deletable by owner"
  on public.import_runs for delete using ((select auth.uid()) = user_id);

create policy "Import manifest pages are readable by owner"
  on public.import_manifest_pages for select using ((select auth.uid()) = user_id);
create policy "Import manifest pages are insertable by owner"
  on public.import_manifest_pages for insert with check ((select auth.uid()) = user_id);
create policy "Import manifest pages are updateable by owner"
  on public.import_manifest_pages for update
  using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);
create policy "Import manifest pages are deletable by owner"
  on public.import_manifest_pages for delete using ((select auth.uid()) = user_id);

create policy "Import files are readable by owner"
  on public.import_files for select using ((select auth.uid()) = user_id);
create policy "Import files are insertable by owner"
  on public.import_files for insert with check ((select auth.uid()) = user_id);
create policy "Import files are updateable by owner"
  on public.import_files for update
  using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);
create policy "Import files are deletable by owner"
  on public.import_files for delete using ((select auth.uid()) = user_id);

create policy "Import parts are readable by owner"
  on public.import_file_parts for select using ((select auth.uid()) = user_id);
create policy "Import parts are insertable by owner"
  on public.import_file_parts for insert with check ((select auth.uid()) = user_id);
create policy "Import parts are updateable by owner"
  on public.import_file_parts for update
  using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);
create policy "Import parts are deletable by owner"
  on public.import_file_parts for delete using ((select auth.uid()) = user_id);

create policy "Import jobs are readable by owner"
  on public.import_jobs for select using ((select auth.uid()) = user_id);
create policy "Import jobs are insertable by owner"
  on public.import_jobs for insert with check ((select auth.uid()) = user_id);
create policy "Import jobs are updateable by owner"
  on public.import_jobs for update
  using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);
create policy "Import jobs are deletable by owner"
  on public.import_jobs for delete using ((select auth.uid()) = user_id);

create policy "Import errors are readable by owner"
  on public.import_errors for select using ((select auth.uid()) = user_id);
create policy "Import errors are insertable by owner"
  on public.import_errors for insert with check ((select auth.uid()) = user_id);
create policy "Import errors are updateable by owner"
  on public.import_errors for update
  using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);
create policy "Import errors are deletable by owner"
  on public.import_errors for delete using ((select auth.uid()) = user_id);

drop trigger if exists import_runs_set_updated_at on public.import_runs;
create trigger import_runs_set_updated_at
before update on public.import_runs
for each row execute function public.set_updated_at();

drop trigger if exists import_files_set_updated_at on public.import_files;
create trigger import_files_set_updated_at
before update on public.import_files
for each row execute function public.set_updated_at();

drop trigger if exists import_file_parts_set_updated_at on public.import_file_parts;
create trigger import_file_parts_set_updated_at
before update on public.import_file_parts
for each row execute function public.set_updated_at();

drop trigger if exists import_jobs_set_updated_at on public.import_jobs;
create trigger import_jobs_set_updated_at
before update on public.import_jobs
for each row execute function public.set_updated_at();

insert into storage.buckets (id, name, public, file_size_limit)
values ('health-imports', 'health-imports', false, 20971520)
on conflict (id) do update
set public = excluded.public,
    file_size_limit = excluded.file_size_limit;

drop policy if exists "Import objects are insertable by owner" on storage.objects;
create policy "Import objects are insertable by owner"
  on storage.objects for insert to authenticated
  with check (
    bucket_id = 'health-imports'
    and array_length(storage.foldername(name), 1) = 5
    and (storage.foldername(name))[1] = 'imports'
    and (storage.foldername(name))[2] = (select auth.uid()::text)
    and storage.filename(name) ~ '^part-[0-9]+$'
  );

drop policy if exists "Import objects are readable by owner" on storage.objects;
create policy "Import objects are readable by owner"
  on storage.objects for select to authenticated
  using (
    bucket_id = 'health-imports'
    and array_length(storage.foldername(name), 1) = 5
    and (storage.foldername(name))[1] = 'imports'
    and (storage.foldername(name))[2] = (select auth.uid()::text)
    and storage.filename(name) ~ '^part-[0-9]+$'
  );

drop policy if exists "Import objects are deletable by owner" on storage.objects;
create policy "Import objects are deletable by owner"
  on storage.objects for delete to authenticated
  using (
    bucket_id = 'health-imports'
    and array_length(storage.foldername(name), 1) = 5
    and (storage.foldername(name))[1] = 'imports'
    and (storage.foldername(name))[2] = (select auth.uid()::text)
    and storage.filename(name) ~ '^part-[0-9]+$'
  );
