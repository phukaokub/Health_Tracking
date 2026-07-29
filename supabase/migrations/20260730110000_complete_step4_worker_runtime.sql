-- Complete the Step 4 runtime contract discovered during hosted verification:
-- verified upload files are the only parseable source state, file progress is
-- idempotent across retries, and raw objects can be removed only after the
-- approved 24-hour recovery window.

create table public.parser_file_completions (
  job_id uuid not null,
  import_id uuid not null,
  import_file_id uuid not null,
  user_id uuid not null,
  normalized_record_count bigint not null default 0,
  warning_codes text[] not null default '{}'::text[],
  completed_at timestamptz not null default now(),
  primary key (job_id, import_file_id),
  constraint parser_file_completions_job_fk
    foreign key (job_id, import_id, user_id)
    references public.import_jobs (id, import_id, user_id) on delete cascade,
  constraint parser_file_completions_file_fk
    foreign key (import_file_id, import_id, user_id)
    references public.import_files (id, import_id, user_id) on delete cascade,
  constraint parser_file_completions_count_check
    check (normalized_record_count >= 0),
  constraint parser_file_completions_warning_codes_check
    check (cardinality(warning_codes) <= 32)
);

create index parser_file_completions_owner_idx
  on public.parser_file_completions (user_id, import_id, completed_at desc);

alter table public.parser_file_completions enable row level security;

create policy "Parser file completions are readable by owner"
  on public.parser_file_completions for select to authenticated
  using ((select auth.uid()) = user_id);

revoke all on public.parser_file_completions from public, anon, authenticated;
grant select on public.parser_file_completions to authenticated;

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
  where job.attempt_count < job.max_attempts
    and (
      job.state = 'queued'
      or (job.state in ('leased', 'processing') and job.lease_expires_at < now())
    )
  order by job.created_at, job.id
  for update skip locked
  limit 1;

  if not found then
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
    and run.state in ('queued', 'uploaded', 'processing');
  return next;
end;
$$;

create or replace function public.worker_import_source(
  p_job_id uuid,
  p_lease_generation uuid
)
returns table(id uuid, logical_bytes bigint, content_sha256 text, parts jsonb)
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_subject text := (select auth.jwt() ->> 'sub');
begin
  if coalesce((select auth.jwt() -> 'app_metadata' ->> 'import_worker'), '') <> 'true'
     or v_subject is null then
    raise exception using errcode = 'P0001', message = 'worker_configuration_invalid';
  end if;
  if not exists (
    select 1
    from public.import_jobs job
    where job.id = p_job_id
      and job.worker_subject = v_subject
      and job.lease_generation = p_lease_generation
      and job.state = 'processing'
      and job.lease_expires_at >= now()
  ) then
    raise exception using errcode = 'P0001', message = 'lease_lost';
  end if;

  return query
    select
      file.id,
      file.logical_bytes,
      file.content_sha256,
      coalesce(
        jsonb_agg(
          jsonb_build_object(
            'part_index', part.part_index,
            'byte_length', part.byte_length,
            'content_sha256', part.content_sha256,
            'object_path', part.object_path
          )
          order by part.part_index
        ) filter (where part.id is not null),
        '[]'::jsonb
      )
    from public.import_files file
    join public.import_jobs job
      on job.import_id = file.import_id and job.user_id = file.user_id
    left join public.import_file_parts part on part.file_id = file.id
    where job.id = p_job_id
      and file.inclusion_state = 'verified'
    group by file.id, file.logical_bytes, file.content_sha256
    order by file.id;
end;
$$;

create or replace function public.worker_complete_import_file(
  p_job_id uuid,
  p_lease_generation uuid,
  p_import_file_id uuid,
  p_normalized_record_count bigint default 0,
  p_warning_codes text[] default '{}'
)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_subject text := (select auth.jwt() ->> 'sub');
  v_job public.import_jobs;
  v_checkpoint_count bigint;
  v_inserted integer;
begin
  if coalesce((select auth.jwt() -> 'app_metadata' ->> 'import_worker'), '') <> 'true'
     or v_subject is null
     or p_normalized_record_count < 0
     or cardinality(p_warning_codes) > 32
     or exists (
       select 1
       from unnest(coalesce(p_warning_codes, '{}'::text[])) as code
       where code !~ '^[a-z0-9_]{3,80}$'
     ) then
    raise exception using errcode = 'P0001', message = 'worker_configuration_invalid';
  end if;

  select * into v_job
  from public.import_jobs job
  where job.id = p_job_id
    and job.worker_subject = v_subject
    and job.lease_generation = p_lease_generation
    and job.state = 'processing'
    and job.lease_expires_at >= now()
  for update;
  if not found then
    raise exception using errcode = 'P0001', message = 'lease_lost';
  end if;
  if not exists (
    select 1
    from public.import_files file
    where file.id = p_import_file_id
      and file.import_id = v_job.import_id
      and file.user_id = v_job.user_id
      and file.inclusion_state = 'verified'
  ) then
    raise exception using errcode = 'P0001', message = 'source_file_invalid';
  end if;

  select coalesce(sum(checkpoint.normalized_record_count), 0)
  into v_checkpoint_count
  from public.parser_file_checkpoints checkpoint
  where checkpoint.job_id = p_job_id
    and checkpoint.import_file_id = p_import_file_id;
  if v_checkpoint_count <> p_normalized_record_count then
    raise exception using errcode = 'P0001', message = 'file_record_count_mismatch';
  end if;

  insert into public.parser_file_completions (
    job_id, import_id, import_file_id, user_id,
    normalized_record_count, warning_codes
  ) values (
    p_job_id, v_job.import_id, p_import_file_id, v_job.user_id,
    p_normalized_record_count, coalesce(p_warning_codes, '{}'::text[])
  )
  on conflict (job_id, import_file_id) do nothing;
  get diagnostics v_inserted = row_count;

  if v_inserted = 1 then
    update public.import_jobs
    set processed_file_count = processed_file_count + 1,
        warning_codes = (
          select coalesce(array_agg(distinct code order by code), '{}'::text[])
          from unnest(warning_codes || coalesce(p_warning_codes, '{}'::text[])) as code
        ),
        last_checkpoint_at = now(),
        updated_at = now()
    where id = p_job_id;
  end if;
  return true;
end;
$$;

create or replace function public.worker_retry_import_job(
  p_job_id uuid,
  p_lease_generation uuid,
  p_warning_code text
)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_subject text := (select auth.jwt() ->> 'sub');
  v_job public.import_jobs;
  v_next_state text;
begin
  if coalesce((select auth.jwt() -> 'app_metadata' ->> 'import_worker'), '') <> 'true'
     or v_subject is null
     or p_warning_code !~ '^[a-z0-9_]{3,80}$' then
    raise exception using errcode = 'P0001', message = 'worker_configuration_invalid';
  end if;

  select * into v_job
  from public.import_jobs job
  where job.id = p_job_id
    and job.worker_subject = v_subject
    and job.lease_generation = p_lease_generation
    and job.state = 'processing'
    and job.lease_expires_at >= now()
  for update;
  if not found then
    raise exception using errcode = 'P0001', message = 'lease_lost';
  end if;

  v_next_state := case
    when v_job.attempt_count < v_job.max_attempts then 'queued'
    else 'failed'
  end;

  update public.import_jobs
  set state = v_next_state,
      worker_subject = null,
      lease_generation = null,
      lease_expires_at = null,
      warning_codes = (
        select coalesce(array_agg(distinct code order by code), '{}'::text[])
        from unnest(warning_codes || array[p_warning_code]) as code
      ),
      updated_at = now()
  where id = p_job_id;

  update public.import_runs
  set state = v_next_state,
      raw_parts_recovery_until = case
        when v_next_state = 'failed' then now() + interval '24 hours'
        else raw_parts_recovery_until
      end,
      updated_at = now()
  where id = v_job.import_id and user_id = v_job.user_id;

  return v_next_state;
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
  v_job public.import_jobs;
  v_expected_files integer;
begin
  if coalesce((select auth.jwt() -> 'app_metadata' ->> 'import_worker'), '') <> 'true'
     or v_subject is null
     or p_terminal_state not in ('completed', 'completed_with_warnings', 'failed', 'cancelled')
     or cardinality(p_warning_codes) > 32
     or exists (
       select 1
       from unnest(coalesce(p_warning_codes, '{}'::text[])) as code
       where code !~ '^[a-z0-9_]{3,80}$'
     ) then
    raise exception using errcode = 'P0001', message = 'worker_configuration_invalid';
  end if;

  select * into v_job
  from public.import_jobs job
  where job.id = p_job_id
    and job.worker_subject = v_subject
    and job.lease_generation = p_lease_generation
    and job.state = 'processing'
    and job.lease_expires_at >= now()
  for update;
  if not found then
    return false;
  end if;

  if p_terminal_state in ('completed', 'completed_with_warnings') then
    select count(*) into v_expected_files
    from public.import_files file
    where file.import_id = v_job.import_id
      and file.user_id = v_job.user_id
      and file.inclusion_state = 'verified';
    if v_expected_files = 0 or v_job.processed_file_count <> v_expected_files then
      raise exception using errcode = 'P0001', message = 'job_files_incomplete';
    end if;
  end if;

  update public.import_jobs
  set state = case
        when p_terminal_state = 'completed_with_warnings' then 'completed'
        else p_terminal_state
      end,
      warning_codes = (
        select coalesce(array_agg(distinct code order by code), '{}'::text[])
        from unnest(warning_codes || coalesce(p_warning_codes, '{}'::text[])) as code
      ),
      worker_subject = null,
      lease_generation = null,
      lease_expires_at = null,
      updated_at = now()
  where id = p_job_id;

  update public.import_runs
  set state = p_terminal_state,
      raw_parts_recovery_until = now() + interval '24 hours',
      updated_at = now()
  where id = v_job.import_id and user_id = v_job.user_id;
  return true;
end;
$$;

create or replace function public.worker_has_cleanup_import_object(
  p_bucket_id text,
  p_object_name text
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce((select auth.jwt() -> 'app_metadata' ->> 'import_worker'), '') = 'true'
    and exists (
      select 1
      from public.import_file_parts part
      join public.import_runs run
        on run.id = part.import_id and run.user_id = part.user_id
      where p_bucket_id = 'health-imports'
        and part.object_path = p_object_name
        and run.raw_parts_recovery_until <= now()
        and run.state in ('completed', 'completed_with_warnings', 'failed', 'cancelled')
        and not exists (
          select 1
          from public.import_jobs job
          where job.import_id = run.id
            and job.state in ('leased', 'processing')
            and job.lease_expires_at >= now()
        )
    );
$$;

create policy "Recovery-expired worker can delete private import parts"
  on storage.objects for delete to authenticated
  using (
    bucket_id = 'health-imports'
    and public.worker_has_cleanup_import_object(bucket_id, name)
  );

create or replace function public.worker_raw_cleanup_source(p_limit integer default 25)
returns table(import_id uuid, object_paths text[])
language sql
security definer
set search_path = ''
as $$
  select
    run.id,
    coalesce(array_agg(part.object_path order by part.object_path), '{}'::text[])
  from public.import_runs run
  join public.import_file_parts part on part.import_id = run.id and part.user_id = run.user_id
  where coalesce((select auth.jwt() -> 'app_metadata' ->> 'import_worker'), '') = 'true'
    and run.raw_parts_recovery_until <= now()
    and run.state in ('completed', 'completed_with_warnings', 'failed', 'cancelled')
    and part.state <> 'deleted'
    and not exists (
      select 1
      from public.import_jobs job
      where job.import_id = run.id
        and job.state in ('leased', 'processing')
        and job.lease_expires_at >= now()
    )
  group by run.id, run.raw_parts_recovery_until
  order by run.raw_parts_recovery_until, run.id
  limit least(greatest(coalesce(p_limit, 25), 1), 100)
$$;

create or replace function public.worker_finish_raw_cleanup(p_import_id uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
begin
  if coalesce((select auth.jwt() -> 'app_metadata' ->> 'import_worker'), '') <> 'true' then
    raise exception using errcode = 'P0001', message = 'worker_configuration_invalid';
  end if;
  if not exists (
    select 1
    from public.import_runs run
    where run.id = p_import_id
      and run.raw_parts_recovery_until <= now()
      and run.state in ('completed', 'completed_with_warnings', 'failed', 'cancelled')
      and not exists (
        select 1
        from public.import_jobs job
        where job.import_id = run.id
          and job.state in ('leased', 'processing')
          and job.lease_expires_at >= now()
      )
  ) then
    raise exception using errcode = 'P0001', message = 'cleanup_not_allowed';
  end if;
  if exists (
    select 1
    from public.import_file_parts part
    join storage.objects object
      on object.bucket_id = 'health-imports' and object.name = part.object_path
    where part.import_id = p_import_id
  ) then
    raise exception using errcode = 'P0001', message = 'cleanup_objects_remain';
  end if;

  update public.import_file_parts
  set state = 'deleted'
  where import_id = p_import_id;
  update public.import_files
  set inclusion_state = 'deleted'
  where import_id = p_import_id and inclusion_state = 'verified';
  update public.import_runs
  set raw_parts_recovery_until = null, updated_at = now()
  where id = p_import_id;
  return true;
end;
$$;

revoke all on function public.worker_claim_import_job(text, integer)
  from public, anon, authenticated;
revoke all on function public.worker_import_source(uuid, uuid)
  from public, anon, authenticated;
revoke all on function public.worker_complete_import_file(uuid, uuid, uuid, bigint, text[])
  from public, anon, authenticated;
revoke all on function public.worker_retry_import_job(uuid, uuid, text)
  from public, anon, authenticated;
revoke all on function public.worker_finish_import_job(uuid, uuid, text, text[])
  from public, anon, authenticated;
revoke all on function public.worker_has_cleanup_import_object(text, text)
  from public, anon, authenticated;
revoke all on function public.worker_raw_cleanup_source(integer)
  from public, anon, authenticated;
revoke all on function public.worker_finish_raw_cleanup(uuid)
  from public, anon, authenticated;

grant execute on function public.worker_claim_import_job(text, integer)
  to authenticated;
grant execute on function public.worker_import_source(uuid, uuid)
  to authenticated;
grant execute on function public.worker_complete_import_file(uuid, uuid, uuid, bigint, text[])
  to authenticated;
grant execute on function public.worker_retry_import_job(uuid, uuid, text)
  to authenticated;
grant execute on function public.worker_finish_import_job(uuid, uuid, text, text[])
  to authenticated;
grant execute on function public.worker_has_cleanup_import_object(text, text)
  to authenticated;
grant execute on function public.worker_raw_cleanup_source(integer)
  to authenticated;
grant execute on function public.worker_finish_raw_cleanup(uuid)
  to authenticated;
