-- Huawei parser v3 release contract.
-- Reprocessing is owner-scoped, reuses verified private Storage parts, and
-- never accepts source bytes or source identifiers from the client.

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conrelid = 'public.import_files'::regclass
      and conname = 'import_files_parser_version_target_check'
  ) then
    alter table public.import_files
      add constraint import_files_parser_version_target_check
      check (
        parser_version_target is null
        or parser_version_target ~ '^[a-z0-9][a-z0-9._-]{0,63}$'
      );
  end if;
end;
$$;

create or replace function public.enforce_health_sample_source_precedence()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
  if new.canonical_day is null then
    select case
      when exists (
        select 1 from pg_catalog.pg_timezone_names zone
        where zone.name = run.timezone_candidate
      ) then (new.started_at at time zone run.timezone_candidate)::date
      else (new.started_at at time zone 'UTC')::date
    end
    into new.canonical_day
    from public.import_runs run
    where run.id = new.import_id and run.user_id = new.user_id;
  end if;

  if new.source_family = 'huawei_legacy_xls' then
    if new.canonical_day is null then
      return null;
    end if;
    if exists (
      select 1 from public.health_samples sample
      where sample.user_id = new.user_id
        and sample.source_family = 'huawei_health_json'
        and sample.source_type = new.source_type
        and sample.started_at < new.ended_at
        and sample.ended_at >= new.started_at
    ) then
      return null;
    end if;
  elsif new.source_family = 'huawei_health_json' then
    if exists (
      select 1 from public.health_samples sample
      where sample.user_id = new.user_id
        and sample.source_family = 'huawei_legacy_xls'
    ) then
      delete from public.normalization_provenance provenance
      using public.health_samples sample
      where sample.user_id = new.user_id
        and sample.source_family = 'huawei_legacy_xls'
        and sample.source_type = new.source_type
        and sample.started_at < new.ended_at
        and sample.ended_at >= new.started_at
        and provenance.user_id = sample.user_id
        and provenance.import_file_id = sample.import_file_id
        and provenance.source_record_hash = sample.source_record_hash;
      delete from public.health_samples sample
      where sample.user_id = new.user_id
        and sample.source_family = 'huawei_legacy_xls'
        and sample.source_type = new.source_type
        and sample.started_at < new.ended_at
        and sample.ended_at >= new.started_at;
    end if;
  end if;
  return new;
end;
$$;

create or replace function public.worker_import_source(
  p_job_id uuid,
  p_lease_generation uuid
)
returns table(
  id uuid, logical_bytes bigint, content_sha256 text, source_family text,
  content_kind text, timezone_candidate text, batch_sequence_start integer,
  parts jsonb
)
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
    select 1 from public.import_jobs job
    where job.id = p_job_id and job.worker_subject = v_subject
      and job.lease_generation = p_lease_generation
      and job.state = 'processing' and job.lease_expires_at >= now()
  ) then
    raise exception using errcode = 'P0001', message = 'lease_lost';
  end if;

  return query
    select file.id, file.logical_bytes, file.content_sha256, file.source_family,
      file.content_kind, run.timezone_candidate,
      coalesce((
        select min(checkpoint.batch_sequence)
        from public.parser_file_checkpoints checkpoint
        where checkpoint.job_id = p_job_id
          and checkpoint.import_file_id = file.id
      ), (
        select max(checkpoint.batch_sequence) + 1
        from public.parser_file_checkpoints checkpoint
        where checkpoint.job_id = p_job_id
      ), 0)::integer,
      coalesce(jsonb_agg(jsonb_build_object(
        'part_index', part.part_index, 'byte_length', part.byte_length,
        'content_sha256', part.content_sha256, 'object_path', part.object_path
      ) order by part.part_index) filter (where part.id is not null), '[]'::jsonb)
    from public.import_files file
    join public.import_runs run on run.id = file.import_id and run.user_id = file.user_id
    join public.import_jobs job on job.import_id = file.import_id and job.user_id = file.user_id
    left join public.import_file_parts part on part.file_id = file.id
    where job.id = p_job_id and file.inclusion_state = 'verified'
      and not exists (
        select 1
        from public.parser_file_completions completion
        where completion.job_id = job.id
          and completion.import_file_id = file.id
      )
    group by file.id, file.logical_bytes, file.content_sha256, file.source_family,
      file.content_kind, run.timezone_candidate
    order by file.id;
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
       select 1 from unnest(coalesce(p_warning_codes, '{}'::text[])) as code
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
    select 1 from public.import_files file
    where file.id = p_import_file_id
      and file.import_id = v_job.import_id
      and file.user_id = v_job.user_id
      and file.inclusion_state = 'verified'
  ) then
    raise exception using errcode = 'P0001', message = 'source_file_invalid';
  end if;
  if exists (
    select 1 from jsonb_array_elements(p_records) record
    where record->>'kind' not in ('sample', 'sleep_session', 'sleep_stage', 'activity', 'workout')
      or record ? 'raw' or record ? 'route' or record ? 'ecg'
      or record ? 'rri' or record ? 'gps'
  ) then
    raise exception using errcode = 'P0001', message = 'canonical_record_invalid';
  end if;
  if exists (
    select 1 from public.parser_file_checkpoints checkpoint
    where checkpoint.job_id = p_job_id and checkpoint.batch_sequence > p_batch_sequence
  ) then
    raise exception using errcode = 'P0001', message = 'checkpoint_out_of_order';
  end if;

  v_count := jsonb_array_length(p_records);
  select * into v_checkpoint
  from public.parser_file_checkpoints checkpoint
  where checkpoint.job_id = p_job_id and checkpoint.batch_sequence = p_batch_sequence;
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
    source_record_hash, started_at, ended_at, unit, value, parser_version,
    canonical_day
  )
  select
    v_job.user_id, v_job.import_id, p_import_file_id, record->>'dedupe_key',
    record->>'source_family', record->>'source_type', record->>'source_record_hash',
    (record->>'started_at')::timestamptz, (record->>'ended_at')::timestamptz,
    record->>'unit', (record->>'value')::numeric, record->>'parser_version',
    nullif(record->>'canonical_day', '')::date
  from jsonb_array_elements(p_records) record
  where record->>'kind' = 'sample'
  on conflict (user_id, dedupe_key) do nothing;

  insert into public.normalization_provenance (
    user_id, import_id, import_file_id, source_family, source_record_hash,
    parser_version, source_unit, timezone_resolution
  )
  select
    v_job.user_id, v_job.import_id, p_import_file_id, record->>'source_family',
    record->>'source_record_hash', record->>'parser_version',
    coalesce(nullif(record->>'source_unit', ''), 'unknown'),
    coalesce(nullif(record->>'timezone_resolution', ''), 'import_timezone')
  from jsonb_array_elements(p_records) record
  where record->>'kind' = 'sample'
  on conflict do nothing;

  insert into public.sleep_sessions (
    user_id, import_id, import_file_id, dedupe_key, source_record_hash,
    started_at, ended_at, duration_seconds, parser_version
  )
  select
    v_job.user_id, v_job.import_id, p_import_file_id, record->>'dedupe_key',
    record->>'source_record_hash', (record->>'started_at')::timestamptz,
    (record->>'ended_at')::timestamptz, (record->>'duration_seconds')::integer,
    record->>'parser_version'
  from jsonb_array_elements(p_records) record
  where record->>'kind' = 'sleep_session'
  on conflict (user_id, dedupe_key) do nothing;

  insert into public.sleep_stages (
    user_id, sleep_session_id, dedupe_key, stage_code, started_at, ended_at
  )
  select
    v_job.user_id, session.id, record->>'dedupe_key', record->>'stage_code',
    (record->>'started_at')::timestamptz, (record->>'ended_at')::timestamptz
  from jsonb_array_elements(p_records) record
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
    (record->>'started_at')::timestamptz, (record->>'ended_at')::timestamptz,
    (record->>'duration_seconds')::integer, record->>'parser_version'
  from jsonb_array_elements(p_records) record
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
    (record->>'started_at')::timestamptz, (record->>'ended_at')::timestamptz,
    (record->>'duration_seconds')::integer,
    nullif(record->>'distance_metres', '')::numeric,
    nullif(record->>'energy_kilocalories', '')::numeric,
    record->>'parser_version'
  from jsonb_array_elements(p_records) record
  where record->>'kind' = 'workout'
  on conflict (user_id, dedupe_key) do nothing;

  select coalesce(max(part_index), 0) into v_part_index
  from public.import_file_parts where file_id = p_import_file_id;
  perform public.worker_checkpoint_import_job(
    p_job_id, v_job.import_id, p_import_file_id, p_lease_generation,
    v_part_index, 0, p_batch_sequence, v_count, p_warning_codes
  );
  return true;
end;
$$;

create or replace function public.import_api_snapshot(p_import_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select jsonb_build_object(
    'id', run.id, 'state', run.state, 'manifest_version', run.manifest_version,
    'source_kind', run.source_kind, 'timezone_candidate', run.timezone_candidate,
    'total_file_count', run.total_file_count,
    'total_logical_bytes', run.total_logical_bytes, 'cleanup_after', run.cleanup_after,
    'files', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', file.id, 'client_file_id', file.client_file_id,
        'source_reference_hash', file.source_reference_hash,
        'source_family', file.source_family, 'content_kind', file.content_kind,
        'parser_version_target', file.parser_version_target,
        'inclusion_state', file.inclusion_state, 'logical_bytes', file.logical_bytes,
        'content_sha256', file.content_sha256,
        'parts', coalesce((
          select jsonb_agg(jsonb_build_object(
            'id', part.id, 'part_index', part.part_index,
            'byte_offset', part.byte_offset, 'byte_length', part.byte_length,
            'content_sha256', part.content_sha256, 'object_path', part.object_path,
            'state', part.state
          ) order by part.part_index)
          from public.import_file_parts part where part.file_id = file.id
        ), '[]'::jsonb)
      ) order by file.created_at, file.id)
      from public.import_files file where file.import_id = run.id
    ), '[]'::jsonb),
    'job', (select jsonb_build_object(
      'id', job.id, 'state', job.state, 'job_type', job.job_type,
      'parser_version', job.parser_version,
      'processed_file_count', job.processed_file_count,
      'normalized_record_count', job.normalized_record_count,
      'warning_codes', job.warning_codes, 'last_checkpoint_at', job.last_checkpoint_at
    ) from public.import_jobs job
      where job.import_id = run.id and job.job_type = 'parse_import'),
    'normalization', jsonb_build_object(
      'normalized_record_count', coalesce((
        select job.normalized_record_count from public.import_jobs job
        where job.import_id = run.id and job.job_type = 'parse_import'
      ), 0),
      'warning_codes', coalesce((
        select to_jsonb(job.warning_codes) from public.import_jobs job
        where job.import_id = run.id and job.job_type = 'parse_import'
      ), '[]'::jsonb),
      'legacy_backfill', (
        select jsonb_build_object(
          'approved_sheet_count', coalesce(sum(report.approved_sheet_count), 0),
          'excluded_sheet_count', coalesce(sum(report.excluded_sheet_count), 0),
          'unknown_sheet_count', coalesce(sum(report.unknown_sheet_count), 0),
          'covered_date_count', coalesce(sum(report.covered_date_count), 0),
          'candidate_metric_count', coalesce(sum(report.candidate_metric_count), 0),
          'inserted_metric_count', coalesce(sum(report.inserted_metric_count), 0),
          'conflict_metric_count', coalesce(sum(report.conflict_metric_count), 0),
          'ambiguous_cell_count', coalesce(sum(report.ambiguous_cell_count), 0)
        ) from public.legacy_xls_quality_reports report
        where report.import_id = run.id and report.user_id = run.user_id
        having count(*) > 0
      )
    )
  )
  from public.import_runs run
  where run.id = p_import_id and run.user_id = (select auth.uid());
$$;

create or replace function public.create_import_manifest(p_manifest jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := auth.uid();
  v_import_id uuid;
  v_file_id uuid;
  v_file jsonb;
  v_part jsonb;
  v_files jsonb := coalesce(p_manifest->'files', '[]'::jsonb);
  v_parts jsonb;
  v_expected_index integer;
  v_expected_offset bigint;
  v_part_length integer;
  v_file_bytes bigint;
  v_page_bytes bigint;
  v_inclusion_state text;
begin
  if v_user_id is null then raise exception 'authentication required' using errcode = '42501'; end if;
  if jsonb_typeof(p_manifest) <> 'object' or jsonb_typeof(v_files) <> 'array' then
    raise exception 'manifest must be an object with a files array' using errcode = '22023';
  end if;
  if (p_manifest->>'manifest_version')::integer <> 1
     or p_manifest->>'source_kind' not in ('directory', 'zip')
     or jsonb_array_length(v_files) > 1000 then
    raise exception 'invalid manifest bounds' using errcode = '22023';
  end if;
  if (p_manifest->>'total_file_count')::integer < jsonb_array_length(v_files)
     or (p_manifest->>'total_file_count')::integer > 5000 then
    raise exception 'total file count is outside manifest bounds' using errcode = '22023';
  end if;
  if coalesce(p_manifest->>'timezone_candidate', '') <> ''
     and char_length(p_manifest->>'timezone_candidate') > 64 then
    raise exception 'timezone candidate is too long' using errcode = '22023';
  end if;
  select coalesce(sum((value->>'logical_bytes')::bigint), 0) into v_page_bytes
  from jsonb_array_elements(v_files);
  if v_page_bytes > (p_manifest->>'total_logical_bytes')::bigint then
    raise exception 'first page bytes exceed import total' using errcode = '22023';
  end if;

  select id into v_import_id from public.import_runs
  where user_id = v_user_id
    and client_idempotency_key = (p_manifest->>'client_idempotency_key')::uuid;
  if v_import_id is not null then
    if not exists (
      select 1 from public.import_runs run
      join public.import_manifest_pages page on page.import_id = run.id and page.page_index = 0
      where run.id = v_import_id and run.manifest_version = 1
        and run.source_kind = p_manifest->>'source_kind'
        and run.total_file_count = (p_manifest->>'total_file_count')::integer
        and run.total_logical_bytes = (p_manifest->>'total_logical_bytes')::bigint
        and page.content_sha256 = p_manifest->>'page_content_sha256'
    ) then
      raise exception 'idempotency key is already bound to another manifest' using errcode = 'HT409';
    end if;
    return public.import_api_snapshot(v_import_id);
  end if;

  v_import_id := gen_random_uuid();
  insert into public.import_runs (
    id, user_id, client_idempotency_key, state, manifest_version, source_kind,
    timezone_candidate, total_file_count, total_logical_bytes
  ) values (
    v_import_id, v_user_id, (p_manifest->>'client_idempotency_key')::uuid,
    'uploading', 1, p_manifest->>'source_kind',
    nullif(p_manifest->>'timezone_candidate', ''),
    (p_manifest->>'total_file_count')::integer,
    (p_manifest->>'total_logical_bytes')::bigint
  );
  insert into public.import_manifest_pages (
    import_id, user_id, page_index, content_sha256, file_count, logical_bytes
  ) values (v_import_id, v_user_id, 0, p_manifest->>'page_content_sha256',
            jsonb_array_length(v_files), v_page_bytes);

  for v_file in select value from jsonb_array_elements(v_files) loop
    v_file_id := gen_random_uuid();
    v_file_bytes := (v_file->>'logical_bytes')::bigint;
    v_inclusion_state := coalesce(v_file->>'inclusion_state', 'planned');
    if v_inclusion_state not in ('planned', 'skipped_duplicate', 'excluded') then
      raise exception 'invalid initial file inclusion state' using errcode = '22023';
    end if;
    insert into public.import_files (
      id, import_id, user_id, client_file_id, source_reference_hash,
      source_family, content_kind, inclusion_state, logical_bytes, content_sha256,
      parser_version_target
    ) values (
      v_file_id, v_import_id, v_user_id, (v_file->>'client_file_id')::uuid,
      v_file->>'source_reference_hash', v_file->>'source_family',
      v_file->>'content_kind', v_inclusion_state, v_file_bytes,
      v_file->>'content_sha256',
      coalesce(nullif(v_file->>'parser_version_target', ''), 'huawei-json-v3')
    );
    v_parts := coalesce(v_file->'parts', '[]'::jsonb);
    if jsonb_typeof(v_parts) <> 'array'
       or (v_inclusion_state <> 'planned' and jsonb_array_length(v_parts) <> 0) then
      raise exception 'file parts are invalid for the inclusion state' using errcode = '22023';
    end if;
    v_expected_index := 0; v_expected_offset := 0;
    for v_part in select value from jsonb_array_elements(v_parts) loop
      v_part_length := (v_part->>'byte_length')::integer;
      if (v_part->>'part_index')::integer <> v_expected_index
         or (v_part->>'byte_offset')::bigint <> v_expected_offset
         or v_part_length < 1 or v_part_length > 20971520 then
        raise exception 'file parts must be contiguous and bounded' using errcode = '22023';
      end if;
      insert into public.import_file_parts (
        file_id, import_id, user_id, part_index, byte_offset, byte_length,
        content_sha256, object_path
      ) values (
        v_file_id, v_import_id, v_user_id, v_expected_index, v_expected_offset,
        v_part_length, v_part->>'content_sha256',
        format('imports/%s/%s/%s/part-%s', v_user_id, v_import_id, v_file_id, v_expected_index)
      );
      v_expected_index := v_expected_index + 1;
      v_expected_offset := v_expected_offset + v_part_length;
    end loop;
    if v_inclusion_state = 'planned' and v_expected_offset <> v_file_bytes then
      raise exception 'planned part lengths do not match logical file size' using errcode = '22023';
    end if;
  end loop;

  if (select coalesce(sum(logical_bytes), 0) from public.import_files where import_id = v_import_id)
       > (p_manifest->>'total_logical_bytes')::bigint
     or ((p_manifest->>'total_file_count')::integer = jsonb_array_length(v_files)
       and v_page_bytes <> (p_manifest->>'total_logical_bytes')::bigint) then
    raise exception 'manifest totals do not match files' using errcode = '22023';
  end if;
  return public.import_api_snapshot(v_import_id);
exception
  when unique_violation then
    select id into v_import_id from public.import_runs
    where user_id = v_user_id
      and client_idempotency_key = (p_manifest->>'client_idempotency_key')::uuid;
    if v_import_id is null then raise; end if;
    return public.import_api_snapshot(v_import_id);
end;
$$;

create or replace function public.append_import_manifest_page(p_import_id uuid, p_page jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := auth.uid();
  v_state text;
  v_total_file_count integer;
  v_total_logical_bytes bigint;
  v_existing_file_count integer;
  v_existing_logical_bytes bigint;
  v_expected_page_index integer;
  v_page_index integer := (p_page->>'page_index')::integer;
  v_page_hash text := p_page->>'page_content_sha256';
  v_files jsonb := coalesce(p_page->'files', '[]'::jsonb);
  v_page_bytes bigint;
  v_file jsonb;
  v_file_id uuid;
  v_file_bytes bigint;
  v_inclusion_state text;
  v_parts jsonb;
  v_part jsonb;
  v_expected_index integer;
  v_expected_offset bigint;
  v_part_length integer;
begin
  if v_user_id is null then raise exception 'authentication required' using errcode = '42501'; end if;
  if jsonb_typeof(p_page) <> 'object' or jsonb_typeof(v_files) <> 'array'
     or jsonb_array_length(v_files) < 1 or jsonb_array_length(v_files) > 1000
     or v_page_index < 1 or v_page_hash !~ '^[0-9a-f]{64}$' then
    raise exception 'invalid manifest page' using errcode = '22023';
  end if;
  select state, total_file_count, total_logical_bytes
  into v_state, v_total_file_count, v_total_logical_bytes
  from public.import_runs where id = p_import_id and user_id = v_user_id for update;
  if v_state is null then raise exception 'import not found' using errcode = 'P0002'; end if;
  if v_state <> 'uploading' then raise exception 'manifest pages require an uploading import' using errcode = '22023'; end if;
  if exists (select 1 from public.import_manifest_pages where import_id = p_import_id and page_index = v_page_index and content_sha256 = v_page_hash) then
    return public.import_api_snapshot(p_import_id);
  end if;
  if exists (select 1 from public.import_manifest_pages where import_id = p_import_id and (page_index = v_page_index or content_sha256 = v_page_hash)) then
    raise exception 'manifest page conflicts with an existing page' using errcode = '23505';
  end if;
  select coalesce(max(page_index), -1) + 1 into v_expected_page_index
  from public.import_manifest_pages where import_id = p_import_id;
  if v_page_index <> v_expected_page_index then raise exception 'manifest pages must be appended in order' using errcode = '22023'; end if;
  select count(*), coalesce(sum(logical_bytes), 0) into v_existing_file_count, v_existing_logical_bytes
  from public.import_files where import_id = p_import_id;
  select coalesce(sum((value->>'logical_bytes')::bigint), 0) into v_page_bytes
  from jsonb_array_elements(v_files);
  if v_existing_file_count + jsonb_array_length(v_files) > v_total_file_count
     or v_existing_logical_bytes + v_page_bytes > v_total_logical_bytes then
    raise exception 'manifest page exceeds declared import totals' using errcode = '22023';
  end if;
  insert into public.import_manifest_pages (import_id, user_id, page_index, content_sha256, file_count, logical_bytes)
  values (p_import_id, v_user_id, v_page_index, v_page_hash, jsonb_array_length(v_files), v_page_bytes);
  for v_file in select value from jsonb_array_elements(v_files) loop
    v_file_id := gen_random_uuid(); v_file_bytes := (v_file->>'logical_bytes')::bigint;
    v_inclusion_state := coalesce(v_file->>'inclusion_state', 'planned');
    if v_inclusion_state not in ('planned', 'skipped_duplicate', 'excluded') then raise exception 'invalid initial file inclusion state' using errcode = '22023'; end if;
    insert into public.import_files (
      id, import_id, user_id, client_file_id, source_reference_hash, source_family,
      content_kind, inclusion_state, logical_bytes, content_sha256, parser_version_target
    ) values (
      v_file_id, p_import_id, v_user_id, (v_file->>'client_file_id')::uuid,
      v_file->>'source_reference_hash', v_file->>'source_family', v_file->>'content_kind',
      v_inclusion_state, v_file_bytes, v_file->>'content_sha256',
      coalesce(nullif(v_file->>'parser_version_target', ''), 'huawei-json-v3')
    );
    v_parts := coalesce(v_file->'parts', '[]'::jsonb);
    if jsonb_typeof(v_parts) <> 'array' or (v_inclusion_state <> 'planned' and jsonb_array_length(v_parts) <> 0) then
      raise exception 'file parts are invalid for the inclusion state' using errcode = '22023';
    end if;
    v_expected_index := 0; v_expected_offset := 0;
    for v_part in select value from jsonb_array_elements(v_parts) loop
      v_part_length := (v_part->>'byte_length')::integer;
      if (v_part->>'part_index')::integer <> v_expected_index
         or (v_part->>'byte_offset')::bigint <> v_expected_offset
         or v_part_length < 1 or v_part_length > 20971520 then
        raise exception 'file parts must be contiguous and bounded' using errcode = '22023';
      end if;
      insert into public.import_file_parts (
        file_id, import_id, user_id, part_index, byte_offset, byte_length, content_sha256, object_path
      ) values (
        v_file_id, p_import_id, v_user_id, v_expected_index, v_expected_offset, v_part_length,
        v_part->>'content_sha256', format('imports/%s/%s/%s/part-%s', v_user_id, p_import_id, v_file_id, v_expected_index)
      );
      v_expected_index := v_expected_index + 1; v_expected_offset := v_expected_offset + v_part_length;
    end loop;
    if v_inclusion_state = 'planned' and v_expected_offset <> v_file_bytes then raise exception 'planned part lengths do not match logical file size' using errcode = '22023'; end if;
  end loop;
  if v_existing_file_count + jsonb_array_length(v_files) = v_total_file_count
     and v_existing_logical_bytes + v_page_bytes <> v_total_logical_bytes then
    raise exception 'final manifest page does not match declared bytes' using errcode = '22023';
  end if;
  return public.import_api_snapshot(p_import_id);
end;
$$;

create or replace function public.requeue_import_for_parser(
  p_import_id uuid,
  p_parser_version text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := auth.uid();
  v_state text;
  v_job_state text;
  v_job_id uuid;
  v_verified_count integer;
begin
  if v_user_id is null then raise exception 'authentication required' using errcode = '42501'; end if;
  if p_parser_version is null or p_parser_version !~ '^[a-z0-9][a-z0-9._-]{0,63}$' then
    raise exception 'invalid parser version' using errcode = '22023';
  end if;
  select run.state into v_state
  from public.import_runs run
  where run.id = p_import_id and run.user_id = v_user_id and run.state <> 'deleted'
  for update;
  if v_state is null then raise exception 'import not found' using errcode = 'P0002'; end if;
  select job.id, job.state into v_job_id, v_job_state
  from public.import_jobs job
  where job.import_id = p_import_id and job.user_id = v_user_id and job.job_type = 'parse_import'
  for update;
  if v_job_id is null then raise exception 'import job not found' using errcode = 'P0002'; end if;
  if v_state in ('queued', 'processing') or v_job_state in ('leased', 'processing', 'queued') then
    return public.import_api_snapshot(p_import_id);
  end if;
  if v_state not in ('completed', 'completed_with_warnings', 'failed')
     or v_job_state not in ('completed', 'failed') then
    raise exception 'import cannot be requeued from its current state' using errcode = '22023';
  end if;
  select count(*) into v_verified_count
  from public.import_files file
  where file.import_id = p_import_id and file.user_id = v_user_id and file.inclusion_state = 'verified';
  if v_verified_count = 0
     or exists (
       select 1
       from public.import_files file
       where file.import_id = p_import_id
         and file.user_id = v_user_id
         and file.inclusion_state = 'verified'
         and file.logical_bytes <> coalesce((
           select sum(part.byte_length)::bigint
           from public.import_file_parts part
           where part.file_id = file.id
             and part.import_id = p_import_id
             and part.user_id = v_user_id
         ), 0)
     )
     or exists (
       select 1 from public.import_file_parts part
       left join storage.objects object
         on object.bucket_id = 'health-imports' and object.name = part.object_path
       where part.import_id = p_import_id and part.user_id = v_user_id
         and (part.state <> 'verified'
           or object.id is null
           or coalesce((object.metadata->>'size')::bigint, -1) <> part.byte_length)
     ) then
    raise exception 'raw_source_unavailable' using errcode = 'P0001';
  end if;

  delete from public.sleep_stages stage
  using public.sleep_sessions session
  where stage.sleep_session_id = session.id
    and session.import_id = p_import_id and session.user_id = v_user_id;
  delete from public.sleep_sessions where import_id = p_import_id and user_id = v_user_id;
  delete from public.activities where import_id = p_import_id and user_id = v_user_id;
  delete from public.workout_sessions where import_id = p_import_id and user_id = v_user_id;
  delete from public.normalization_provenance where import_id = p_import_id and user_id = v_user_id;
  delete from public.health_samples where import_id = p_import_id and user_id = v_user_id;
  delete from public.legacy_xls_quality_reports where import_id = p_import_id and user_id = v_user_id;
  delete from public.parser_file_completions where job_id = v_job_id;
  delete from public.parser_file_checkpoints where job_id = v_job_id;

  update public.import_files
  set parser_version_target = p_parser_version, updated_at = now()
  where import_id = p_import_id and user_id = v_user_id;
  update public.import_jobs
  set state = 'queued', attempt_count = 0, parser_version = null,
      checkpoint = '{}'::jsonb, processed_file_count = 0,
      normalized_record_count = 0, warning_codes = '{}'::text[],
      worker_subject = null, lease_generation = null, lease_expires_at = null,
      last_checkpoint_at = null, updated_at = now()
  where id = v_job_id;
  update public.import_runs
  set state = 'queued', raw_parts_recovery_until = now() + interval '24 hours', updated_at = now()
  where id = p_import_id and user_id = v_user_id;
  return public.import_api_snapshot(p_import_id);
end;
$$;

revoke all on function public.requeue_import_for_parser(uuid, text) from public, anon;
grant execute on function public.requeue_import_for_parser(uuid, text) to authenticated;
