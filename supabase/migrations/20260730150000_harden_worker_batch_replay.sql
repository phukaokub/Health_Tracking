-- A retry may replay a committed batch under a new lease generation. Accept
-- only the same file/count/warnings at that sequence, keep unverified files
-- outside persistence, and bound the encoded RPC payload as well as row count.

create index if not exists health_samples_file_owner_idx
  on public.health_samples (import_file_id, import_id, user_id);
create index if not exists normalization_provenance_file_owner_delete_idx
  on public.normalization_provenance (import_file_id, import_id, user_id);
create index if not exists sleep_sessions_file_owner_idx
  on public.sleep_sessions (import_file_id, import_id, user_id);
create index if not exists activities_file_owner_idx
  on public.activities (import_file_id, import_id, user_id);
create index if not exists workout_sessions_file_owner_idx
  on public.workout_sessions (import_file_id, import_id, user_id);

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
     or coalesce(cardinality(p_warning_codes), 0) > 32
     or exists (
       select 1
       from unnest(coalesce(p_warning_codes, '{}'::text[])) as code
       where code !~ '^[a-z0-9_]{3,80}$'
     ) then
    raise exception using errcode = 'P0001', message = 'worker_configuration_invalid';
  end if;

  select * into v_job
  from public.import_jobs
  where id = p_job_id
    and import_id = p_import_id
    and worker_subject = v_subject
    and lease_generation = p_lease_generation
    and state = 'processing'
    and lease_expires_at >= now()
  for update;
  if not found then
    raise exception using errcode = 'P0001', message = 'lease_lost';
  end if;
  if exists (
    select 1
    from public.parser_file_checkpoints
    where job_id = p_job_id and batch_sequence > p_batch_sequence
  ) then
    raise exception using errcode = 'P0001', message = 'checkpoint_out_of_order';
  end if;

  select * into v_checkpoint
  from public.parser_file_checkpoints
  where job_id = p_job_id and batch_sequence = p_batch_sequence;
  if found then
    if v_checkpoint.import_file_id <> p_import_file_id
       or v_checkpoint.part_index <> p_part_index
       or v_checkpoint.byte_offset <> p_byte_offset
       or v_checkpoint.normalized_record_count <> p_normalized_record_count
       or v_checkpoint.warning_codes <> coalesce(p_warning_codes, '{}'::text[]) then
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
  set checkpoint = jsonb_build_object(
        'file_id', p_import_file_id,
        'part_index', p_part_index,
        'byte_offset', p_byte_offset,
        'batch_sequence', p_batch_sequence
      ),
      warning_codes = (
        select coalesce(array_agg(distinct code order by code), '{}'::text[])
        from unnest(warning_codes || coalesce(p_warning_codes, '{}'::text[])) as code
      ),
      last_checkpoint_at = now(),
      updated_at = now()
  where id = p_job_id;
  return v_checkpoint;
end;
$$;

create or replace function public.worker_persist_normalized_batch(
  p_job_id uuid,
  p_lease_generation uuid,
  p_import_file_id uuid,
  p_batch_sequence integer,
  p_records jsonb,
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
  v_count integer;
  v_part_index integer;
  v_checkpoint public.parser_file_checkpoints;
begin
  if coalesce((select auth.jwt() -> 'app_metadata' ->> 'import_worker'), '') <> 'true'
     or v_subject is null
     or p_batch_sequence < 0
     or jsonb_typeof(p_records) <> 'array'
     or jsonb_array_length(p_records) > 1000
     or pg_column_size(p_records) > 4194304
     or coalesce(cardinality(p_warning_codes), 0) > 32
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
  if exists (
    select 1
    from jsonb_array_elements(p_records) as record
    where record->>'kind' not in (
      'sample', 'sleep_session', 'sleep_stage', 'activity', 'workout'
    )
      or record ? 'raw'
      or record ? 'route'
      or record ? 'ecg'
      or record ? 'rri'
      or record ? 'gps'
  ) then
    raise exception using errcode = 'P0001', message = 'canonical_record_invalid';
  end if;
  if exists (
    select 1
    from public.parser_file_checkpoints checkpoint
    where checkpoint.job_id = p_job_id
      and checkpoint.batch_sequence > p_batch_sequence
  ) then
    raise exception using errcode = 'P0001', message = 'checkpoint_out_of_order';
  end if;

  v_count := jsonb_array_length(p_records);
  select * into v_checkpoint
  from public.parser_file_checkpoints checkpoint
  where checkpoint.job_id = p_job_id
    and checkpoint.batch_sequence = p_batch_sequence;
  if found then
    if v_checkpoint.import_file_id <> p_import_file_id
       or v_checkpoint.normalized_record_count <> v_count
       or v_checkpoint.warning_codes <> coalesce(p_warning_codes, '{}'::text[]) then
      raise exception using errcode = 'P0001', message = 'checkpoint_replay_mismatch';
    end if;
    return true;
  end if;

  insert into public.health_samples (
    user_id, import_id, import_file_id, dedupe_key, source_family, source_type,
    source_record_hash, started_at, ended_at, unit, value, parser_version
  )
  select
    v_job.user_id, v_job.import_id, p_import_file_id, record->>'dedupe_key',
    record->>'source_family', record->>'source_type',
    record->>'source_record_hash', (record->>'started_at')::timestamptz,
    (record->>'ended_at')::timestamptz, record->>'unit',
    (record->>'value')::numeric, record->>'parser_version'
  from jsonb_array_elements(p_records) as record
  where record->>'kind' = 'sample'
  on conflict (user_id, dedupe_key) do nothing;

  insert into public.normalization_provenance (
    user_id, import_id, import_file_id, source_family, source_record_hash,
    parser_version, source_unit, timezone_resolution
  )
  select
    v_job.user_id, v_job.import_id, p_import_file_id, record->>'source_family',
    record->>'source_record_hash', record->>'parser_version',
    record->>'source_unit', 'explicit_offset'
  from jsonb_array_elements(p_records) as record
  where record->>'kind' = 'sample'
  on conflict do nothing;

  insert into public.sleep_sessions (
    user_id, import_id, import_file_id, dedupe_key, source_record_hash,
    started_at, ended_at, duration_seconds, parser_version
  )
  select
    v_job.user_id, v_job.import_id, p_import_file_id, record->>'dedupe_key',
    record->>'source_record_hash', (record->>'started_at')::timestamptz,
    (record->>'ended_at')::timestamptz,
    (record->>'duration_seconds')::integer, record->>'parser_version'
  from jsonb_array_elements(p_records) as record
  where record->>'kind' = 'sleep_session'
  on conflict (user_id, dedupe_key) do nothing;

  insert into public.sleep_stages (
    user_id, sleep_session_id, dedupe_key, stage_code, started_at, ended_at
  )
  select
    v_job.user_id, session.id, record->>'dedupe_key', record->>'stage_code',
    (record->>'started_at')::timestamptz,
    (record->>'ended_at')::timestamptz
  from jsonb_array_elements(p_records) as record
  join public.sleep_sessions session
    on session.user_id = v_job.user_id
   and session.dedupe_key = record->>'parent_dedupe_key'
  where record->>'kind' = 'sleep_stage'
  on conflict (user_id, dedupe_key) do nothing;

  insert into public.activities (
    user_id, import_id, import_file_id, dedupe_key, source_record_hash,
    activity_type, started_at, ended_at, duration_seconds, parser_version
  )
  select
    v_job.user_id, v_job.import_id, p_import_file_id, record->>'dedupe_key',
    record->>'source_record_hash', record->>'activity_type',
    (record->>'started_at')::timestamptz,
    (record->>'ended_at')::timestamptz,
    (record->>'duration_seconds')::integer, record->>'parser_version'
  from jsonb_array_elements(p_records) as record
  where record->>'kind' = 'activity'
  on conflict (user_id, dedupe_key) do nothing;

  insert into public.workout_sessions (
    user_id, import_id, import_file_id, dedupe_key, source_record_hash,
    workout_type, started_at, ended_at, duration_seconds, distance_metres,
    energy_kilocalories, parser_version
  )
  select
    v_job.user_id, v_job.import_id, p_import_file_id, record->>'dedupe_key',
    record->>'source_record_hash', record->>'workout_type',
    (record->>'started_at')::timestamptz,
    (record->>'ended_at')::timestamptz,
    (record->>'duration_seconds')::integer,
    nullif(record->>'distance_metres', '')::numeric,
    nullif(record->>'energy_kilocalories', '')::numeric,
    record->>'parser_version'
  from jsonb_array_elements(p_records) as record
  where record->>'kind' = 'workout'
  on conflict (user_id, dedupe_key) do nothing;

  select coalesce(max(part_index), 0)
  into v_part_index
  from public.import_file_parts
  where file_id = p_import_file_id;

  perform public.worker_checkpoint_import_job(
    p_job_id, v_job.import_id, p_import_file_id, p_lease_generation,
    v_part_index, 0, p_batch_sequence, v_count, p_warning_codes
  );
  return true;
end;
$$;

revoke all on function public.worker_checkpoint_import_job(
  uuid, uuid, uuid, uuid, integer, bigint, integer, bigint, text[]
) from public, anon, authenticated;
revoke all on function public.worker_persist_normalized_batch(
  uuid, uuid, uuid, integer, jsonb, text[]
) from public, anon, authenticated;

grant execute on function public.worker_checkpoint_import_job(
  uuid, uuid, uuid, uuid, integer, bigint, integer, bigint, text[]
) to authenticated;
grant execute on function public.worker_persist_normalized_batch(
  uuid, uuid, uuid, integer, jsonb, text[]
) to authenticated;
