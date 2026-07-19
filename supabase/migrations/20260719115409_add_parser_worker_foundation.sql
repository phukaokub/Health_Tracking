-- Step 4 worker foundation. This migration adds only local, expand-only state
-- and fixed-signature worker transitions. No Auth identity, trigger, secret, or
-- hosted provider configuration is created here.

alter table public.import_runs
  add column if not exists raw_parts_recovery_until timestamptz;

alter table public.import_jobs
  add column if not exists worker_subject text,
  add column if not exists lease_generation uuid,
  add column if not exists max_attempts integer not null default 3,
  add column if not exists processed_file_count integer not null default 0,
  add column if not exists normalized_record_count bigint not null default 0,
  add column if not exists warning_codes text[] not null default '{}'::text[],
  add column if not exists last_checkpoint_at timestamptz;

alter table public.import_jobs
  add constraint import_jobs_max_attempts_check check (max_attempts between 1 and 10),
  add constraint import_jobs_processed_file_count_check check (processed_file_count >= 0),
  add constraint import_jobs_normalized_record_count_check check (normalized_record_count >= 0),
  add constraint import_jobs_warning_codes_check check (cardinality(warning_codes) <= 32),
  add constraint import_jobs_owner_key unique (id, import_id, user_id);

-- Extend the existing owner snapshot with counts and stable warning codes only.
create or replace function public.import_api_snapshot(p_import_id uuid)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select jsonb_build_object(
    'id', run.id,
    'state', run.state,
    'manifest_version', run.manifest_version,
    'source_kind', run.source_kind,
    'timezone_candidate', run.timezone_candidate,
    'total_file_count', run.total_file_count,
    'total_logical_bytes', run.total_logical_bytes,
    'cleanup_after', run.cleanup_after,
    'files', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', file.id, 'client_file_id', file.client_file_id,
        'source_reference_hash', file.source_reference_hash,
        'source_family', file.source_family, 'content_kind', file.content_kind,
        'inclusion_state', file.inclusion_state, 'logical_bytes', file.logical_bytes,
        'content_sha256', file.content_sha256,
        'parts', coalesce((
          select jsonb_agg(jsonb_build_object(
            'id', part.id, 'part_index', part.part_index, 'byte_offset', part.byte_offset,
            'byte_length', part.byte_length, 'content_sha256', part.content_sha256,
            'object_path', part.object_path, 'state', part.state
          ) order by part.part_index)
          from public.import_file_parts as part where part.file_id = file.id
        ), '[]'::jsonb)
      ) order by file.created_at, file.id)
      from public.import_files as file where file.import_id = run.id
    ), '[]'::jsonb),
    'job', (select jsonb_build_object(
      'id', job.id, 'state', job.state, 'job_type', job.job_type,
      'processed_file_count', job.processed_file_count,
      'normalized_record_count', job.normalized_record_count,
      'warning_codes', job.warning_codes,
      'last_checkpoint_at', job.last_checkpoint_at
    ) from public.import_jobs as job where job.import_id = run.id and job.job_type = 'parse_import')
  )
  from public.import_runs as run
  where run.id = p_import_id and run.user_id = (select auth.uid());
$$;
alter function public.import_api_snapshot(uuid) security definer;

create table public.parser_file_checkpoints (
  id uuid primary key default gen_random_uuid(),
  job_id uuid not null,
  import_id uuid not null,
  import_file_id uuid not null,
  user_id uuid not null,
  part_index integer not null,
  byte_offset bigint not null,
  batch_sequence integer not null,
  parser_version text not null,
  lease_generation uuid not null,
  normalized_record_count bigint not null default 0,
  warning_codes text[] not null default '{}'::text[],
  completed_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  constraint parser_file_checkpoints_job_fk
    foreign key (job_id, import_id, user_id)
    references public.import_jobs (id, import_id, user_id) on delete cascade,
  constraint parser_file_checkpoints_file_fk
    foreign key (import_file_id, import_id, user_id)
    references public.import_files (id, import_id, user_id) on delete cascade,
  constraint parser_file_checkpoints_position_check check (part_index >= 0 and byte_offset >= 0),
  constraint parser_file_checkpoints_sequence_check check (batch_sequence >= 0),
  constraint parser_file_checkpoints_parser_version_check check (char_length(parser_version) between 1 and 64),
  constraint parser_file_checkpoints_normalized_count_check check (normalized_record_count >= 0),
  constraint parser_file_checkpoints_warning_codes_check check (cardinality(warning_codes) <= 32),
  constraint parser_file_checkpoints_batch_key unique (job_id, batch_sequence)
);

create index import_jobs_worker_claim_idx
  on public.import_jobs (state, lease_expires_at, created_at)
  where state in ('queued', 'leased', 'processing');
create index parser_file_checkpoints_job_sequence_idx
  on public.parser_file_checkpoints (job_id, batch_sequence desc);
create index parser_file_checkpoints_owner_idx
  on public.parser_file_checkpoints (user_id, import_id, completed_at desc);
create index import_runs_raw_parts_recovery_idx
  on public.import_runs (raw_parts_recovery_until, state)
  where raw_parts_recovery_until is not null;

alter table public.parser_file_checkpoints enable row level security;
grant select on public.parser_file_checkpoints to authenticated;
create policy "Parser checkpoints are readable by owner"
  on public.parser_file_checkpoints for select to authenticated
  using ((select auth.uid()) = user_id);

-- Worker transitions are callable only by a dedicated Auth identity carrying
-- app_metadata.import_worker=true. The hosted identity/trigger remains out of
-- scope for this source-only migration. Every mutation derives owner/job data
-- from the leased row and checks the lease generation supplied by the worker.

create or replace function public.worker_claim_import_job(
  p_parser_version text,
  p_lease_seconds integer default 240
)
returns table(
  job_id uuid,
  import_id uuid,
  user_id uuid,
  lease_generation uuid,
  lease_expires_at timestamptz,
  attempt_count integer,
  checkpoint jsonb
)
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_job public.import_jobs;
  v_subject text := (select auth.jwt() ->> 'sub');
begin
  if coalesce((select auth.jwt() -> 'app_metadata' ->> 'import_worker'), '') <> 'true'
     or v_subject is null
     or p_parser_version is null
     or char_length(p_parser_version) not between 1 and 64
     or p_lease_seconds not between 30 and 900 then
    raise exception using errcode = 'P0001', message = 'worker_configuration_invalid';
  end if;

  select job.* into v_job
  from public.import_jobs as job
  where job.state = 'queued'
     or (job.state in ('leased', 'processing') and job.lease_expires_at < now())
  order by job.created_at, job.id
  for update skip locked
  limit 1;

  if not found or v_job.attempt_count >= v_job.max_attempts then
    return;
  end if;

  update public.import_jobs as job
  set state = 'processing',
      attempt_count = job.attempt_count + 1,
      worker_subject = v_subject,
      lease_generation = gen_random_uuid(),
      lease_expires_at = now() + make_interval(secs => p_lease_seconds),
      parser_version = p_parser_version,
      updated_at = now()
  where job.id = v_job.id
  returning job.* into v_job;

  job_id := v_job.id;
  import_id := v_job.import_id;
  user_id := v_job.user_id;
  lease_generation := v_job.lease_generation;
  lease_expires_at := v_job.lease_expires_at;
  attempt_count := v_job.attempt_count;
  checkpoint := v_job.checkpoint;

  update public.import_runs as run
  set state = 'processing', updated_at = now()
  where run.id = worker_claim_import_job.import_id
    and run.user_id = worker_claim_import_job.user_id
    and run.state in ('queued', 'uploaded');
  return next;
end;
$$;

create or replace function public.worker_renew_import_job(
  p_job_id uuid,
  p_lease_generation uuid,
  p_lease_seconds integer default 240
)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_subject text := (select auth.jwt() ->> 'sub');
begin
  if coalesce((select auth.jwt() -> 'app_metadata' ->> 'import_worker'), '') <> 'true'
     or v_subject is null or p_lease_seconds not between 30 and 900 then
    raise exception using errcode = 'P0001', message = 'worker_configuration_invalid';
  end if;
  update public.import_jobs
  set lease_expires_at = now() + make_interval(secs => p_lease_seconds), updated_at = now()
  where id = p_job_id and worker_subject = v_subject and lease_generation = p_lease_generation
    and state = 'processing' and lease_expires_at >= now();
  return found;
end;
$$;

create or replace function public.worker_checkpoint_import_job(
  p_job_id uuid,
  p_import_id uuid,
  p_import_file_id uuid,
  p_lease_generation uuid,
  p_part_index integer,
  p_byte_offset bigint,
  p_batch_sequence integer,
  p_normalized_record_count bigint default 0,
  p_warning_codes text[] default '{}'
)
returns public.parser_file_checkpoints
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_subject text := (select auth.jwt() ->> 'sub');
  v_job public.import_jobs;
  v_checkpoint public.parser_file_checkpoints;
begin
  if coalesce((select auth.jwt() -> 'app_metadata' ->> 'import_worker'), '') <> 'true'
     or v_subject is null or p_part_index < 0 or p_byte_offset < 0
     or p_batch_sequence < 0 or p_normalized_record_count < 0
     or cardinality(p_warning_codes) > 32
     or exists (select 1 from unnest(coalesce(p_warning_codes, '{}'::text[])) as code
                where code !~ '^[a-z0-9_]{3,80}$') then
    raise exception using errcode = 'P0001', message = 'worker_configuration_invalid';
  end if;
  select * into v_job from public.import_jobs
  where id = p_job_id and import_id = p_import_id and worker_subject = v_subject
    and lease_generation = p_lease_generation and state = 'processing'
    and lease_expires_at >= now() for update;
  if not found then
    raise exception using errcode = 'P0001', message = 'lease_lost';
  end if;
  if exists (select 1 from public.parser_file_checkpoints where job_id = p_job_id and batch_sequence > p_batch_sequence) then
    raise exception using errcode = 'P0001', message = 'checkpoint_out_of_order';
  end if;
  select * into v_checkpoint from public.parser_file_checkpoints
  where job_id = p_job_id and batch_sequence = p_batch_sequence;
  if found then
    if v_checkpoint.import_file_id <> p_import_file_id
       or v_checkpoint.part_index <> p_part_index
       or v_checkpoint.byte_offset <> p_byte_offset
       or v_checkpoint.lease_generation <> p_lease_generation then
      raise exception using errcode = 'P0001', message = 'checkpoint_replay_mismatch';
    end if;
  else
    insert into public.parser_file_checkpoints (
      job_id, import_id, import_file_id, user_id, part_index, byte_offset,
      batch_sequence, parser_version, lease_generation, normalized_record_count,
      warning_codes
    ) values (
      p_job_id, p_import_id, p_import_file_id, v_job.user_id, p_part_index,
      p_byte_offset, p_batch_sequence, v_job.parser_version, p_lease_generation,
      p_normalized_record_count, coalesce(p_warning_codes, '{}'::text[])
    ) returning * into v_checkpoint;
    update public.import_jobs
    set normalized_record_count = normalized_record_count + p_normalized_record_count
    where id = p_job_id;
  end if;
  update public.import_jobs
  set checkpoint = jsonb_build_object('file_id', p_import_file_id, 'part_index', p_part_index,
                                      'byte_offset', p_byte_offset, 'batch_sequence', p_batch_sequence),
      warning_codes = (select coalesce(array_agg(distinct code order by code), '{}'::text[]) from unnest(warning_codes || coalesce(p_warning_codes, '{}'::text[])) as code),
      last_checkpoint_at = now(), updated_at = now()
  where id = p_job_id;
  return v_checkpoint;
end;
$$;

create or replace function public.worker_finish_import_job(
  p_job_id uuid,
  p_lease_generation uuid,
  p_terminal_state text,
  p_warning_codes text[] default '{}'
)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_subject text := (select auth.jwt() ->> 'sub');
  v_import_id uuid;
  v_user_id uuid;
begin
  if coalesce((select auth.jwt() -> 'app_metadata' ->> 'import_worker'), '') <> 'true'
     or v_subject is null or p_terminal_state not in ('completed','completed_with_warnings','failed','cancelled')
     or cardinality(p_warning_codes) > 32
     or exists (select 1 from unnest(coalesce(p_warning_codes, '{}'::text[])) as code
                where code !~ '^[a-z0-9_]{3,80}$') then
    raise exception using errcode = 'P0001', message = 'worker_configuration_invalid';
  end if;
  update public.import_jobs
  set state = case when p_terminal_state = 'completed_with_warnings' then 'completed' else p_terminal_state end,
      warning_codes = (select coalesce(array_agg(distinct code order by code), '{}'::text[]) from unnest(warning_codes || coalesce(p_warning_codes, '{}'::text[])) as code),
      lease_expires_at = null, updated_at = now()
  where id = p_job_id and worker_subject = v_subject and lease_generation = p_lease_generation
    and state = 'processing' and lease_expires_at >= now()
  returning import_id, user_id into v_import_id, v_user_id;
  if not found then return false; end if;
  update public.import_runs
  set state = p_terminal_state, raw_parts_recovery_until = now() + interval '24 hours', updated_at = now()
  where id = v_import_id and user_id = v_user_id;
  return true;
end;
$$;

create or replace function public.list_worker_raw_cleanup_candidates(p_limit integer default 25)
returns table(import_id uuid, user_id uuid)
language sql
security definer
set search_path = ''
as $$
  select run.id, run.user_id
  from public.import_runs as run
  where coalesce((select auth.jwt() -> 'app_metadata' ->> 'import_worker'), '') = 'true'
    and run.raw_parts_recovery_until <= now()
    and run.state in ('completed', 'completed_with_warnings', 'failed', 'cancelled')
    and not exists (
      select 1 from public.import_jobs as job
      where job.import_id = run.id and job.state in ('leased', 'processing')
        and job.lease_expires_at >= now()
    )
  order by run.raw_parts_recovery_until, run.id
  limit least(greatest(coalesce(p_limit, 25), 1), 100)
$$;

revoke all on function public.worker_claim_import_job(text, integer) from public, anon, authenticated;
revoke all on function public.worker_renew_import_job(uuid, uuid, integer) from public, anon, authenticated;
revoke all on function public.worker_checkpoint_import_job(uuid, uuid, uuid, uuid, integer, bigint, integer, bigint, text[]) from public, anon, authenticated;
revoke all on function public.worker_finish_import_job(uuid, uuid, text, text[]) from public, anon, authenticated;
revoke all on function public.list_worker_raw_cleanup_candidates(integer) from public, anon, authenticated;
grant execute on function public.worker_claim_import_job(text, integer) to authenticated;
grant execute on function public.worker_renew_import_job(uuid, uuid, integer) to authenticated;
grant execute on function public.worker_checkpoint_import_job(uuid, uuid, uuid, uuid, integer, bigint, integer, bigint, text[]) to authenticated;
grant execute on function public.worker_finish_import_job(uuid, uuid, text, text[]) to authenticated;
grant execute on function public.list_worker_raw_cleanup_candidates(integer) to authenticated;
