-- Step 3 import API boundary. All functions are SECURITY INVOKER and therefore
-- retain the authenticated user's RLS scope. No function accepts an owner ID.

drop policy if exists "Import objects are insertable by owner" on storage.objects;
create policy "Import objects are insertable by owner"
  on storage.objects for insert to authenticated
  with check (
    bucket_id = 'health-imports'
    and array_length(storage.foldername(name), 1) = 4
    and (storage.foldername(name))[1] = 'imports'
    and (storage.foldername(name))[2] = (select auth.uid()::text)
    and storage.filename(name) ~ '^part-[0-9]+$'
  );

drop policy if exists "Import objects are readable by owner" on storage.objects;
create policy "Import objects are readable by owner"
  on storage.objects for select to authenticated
  using (
    bucket_id = 'health-imports'
    and array_length(storage.foldername(name), 1) = 4
    and (storage.foldername(name))[1] = 'imports'
    and (storage.foldername(name))[2] = (select auth.uid()::text)
    and storage.filename(name) ~ '^part-[0-9]+$'
  );

drop policy if exists "Import objects are deletable by owner" on storage.objects;
create policy "Import objects are deletable by owner"
  on storage.objects for delete to authenticated
  using (
    bucket_id = 'health-imports'
    and array_length(storage.foldername(name), 1) = 4
    and (storage.foldername(name))[1] = 'imports'
    and (storage.foldername(name))[2] = (select auth.uid()::text)
    and storage.filename(name) ~ '^part-[0-9]+$'
  );

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
        'id', file.id,
        'client_file_id', file.client_file_id,
        'source_reference_hash', file.source_reference_hash,
        'source_family', file.source_family,
        'content_kind', file.content_kind,
        'inclusion_state', file.inclusion_state,
        'logical_bytes', file.logical_bytes,
        'content_sha256', file.content_sha256,
        'parts', coalesce((
          select jsonb_agg(jsonb_build_object(
            'id', part.id,
            'part_index', part.part_index,
            'byte_offset', part.byte_offset,
            'byte_length', part.byte_length,
            'content_sha256', part.content_sha256,
            'object_path', part.object_path,
            'state', part.state
          ) order by part.part_index)
          from public.import_file_parts as part
          where part.file_id = file.id
        ), '[]'::jsonb)
      ) order by file.created_at, file.id)
      from public.import_files as file
      where file.import_id = run.id
    ), '[]'::jsonb),
    'job', (
      select jsonb_build_object('id', job.id, 'state', job.state, 'job_type', job.job_type)
      from public.import_jobs as job
      where job.import_id = run.id and job.job_type = 'parse_import'
    )
  )
  from public.import_runs as run
  where run.id = p_import_id
    and run.user_id = (select auth.uid());
$$;

create or replace function public.create_import_manifest(p_manifest jsonb)
returns jsonb
language plpgsql
security invoker
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
  if v_user_id is null then
    raise exception 'authentication required' using errcode = '42501';
  end if;
  if jsonb_typeof(p_manifest) <> 'object' or jsonb_typeof(v_files) <> 'array' then
    raise exception 'manifest must be an object with a files array' using errcode = '22023';
  end if;
  if (p_manifest->>'manifest_version')::integer <> 1 then
    raise exception 'unsupported manifest version' using errcode = '22023';
  end if;
  if p_manifest->>'source_kind' not in ('directory', 'zip') then
    raise exception 'invalid source kind' using errcode = '22023';
  end if;
  if jsonb_array_length(v_files) > 1000 then
    raise exception 'manifest page exceeds 1000 files' using errcode = '22023';
  end if;
  if (p_manifest->>'total_file_count')::integer < jsonb_array_length(v_files)
     or (p_manifest->>'total_file_count')::integer > 5000 then
    raise exception 'total file count is outside manifest bounds' using errcode = '22023';
  end if;
  if coalesce(p_manifest->>'timezone_candidate', '') <> ''
     and char_length(p_manifest->>'timezone_candidate') > 64 then
    raise exception 'timezone candidate is too long' using errcode = '22023';
  end if;
  select coalesce(sum((value->>'logical_bytes')::bigint), 0)
  into v_page_bytes
  from jsonb_array_elements(v_files);
  if v_page_bytes > (p_manifest->>'total_logical_bytes')::bigint then
    raise exception 'first page bytes exceed import total' using errcode = '22023';
  end if;

  select id into v_import_id
  from public.import_runs
  where user_id = v_user_id
    and client_idempotency_key = (p_manifest->>'client_idempotency_key')::uuid;

  if v_import_id is not null then
    if not exists (
      select 1
      from public.import_runs as run
      join public.import_manifest_pages as page
        on page.import_id = run.id and page.page_index = 0
      where run.id = v_import_id
        and run.manifest_version = 1
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
    v_import_id,
    v_user_id,
    (p_manifest->>'client_idempotency_key')::uuid,
    'uploading',
    1,
    p_manifest->>'source_kind',
    nullif(p_manifest->>'timezone_candidate', ''),
    (p_manifest->>'total_file_count')::integer,
    (p_manifest->>'total_logical_bytes')::bigint
  );

  insert into public.import_manifest_pages (
    import_id, user_id, page_index, content_sha256, file_count, logical_bytes
  ) values (
    v_import_id,
    v_user_id,
    0,
    p_manifest->>'page_content_sha256',
    jsonb_array_length(v_files),
    v_page_bytes
  );

  for v_file in select value from jsonb_array_elements(v_files)
  loop
    v_file_id := gen_random_uuid();
    v_file_bytes := (v_file->>'logical_bytes')::bigint;
    v_inclusion_state := coalesce(v_file->>'inclusion_state', 'planned');
    if v_inclusion_state not in ('planned', 'skipped_duplicate', 'excluded') then
      raise exception 'invalid initial file inclusion state' using errcode = '22023';
    end if;

    insert into public.import_files (
      id, import_id, user_id, client_file_id, source_reference_hash,
      source_family, content_kind, inclusion_state, logical_bytes, content_sha256
    ) values (
      v_file_id,
      v_import_id,
      v_user_id,
      (v_file->>'client_file_id')::uuid,
      v_file->>'source_reference_hash',
      v_file->>'source_family',
      v_file->>'content_kind',
      v_inclusion_state,
      v_file_bytes,
      v_file->>'content_sha256'
    );

    v_parts := coalesce(v_file->'parts', '[]'::jsonb);
    if jsonb_typeof(v_parts) <> 'array' then
      raise exception 'file parts must be an array' using errcode = '22023';
    end if;
    if v_inclusion_state <> 'planned' and jsonb_array_length(v_parts) <> 0 then
      raise exception 'excluded or duplicate files cannot have upload parts' using errcode = '22023';
    end if;

    v_expected_index := 0;
    v_expected_offset := 0;
    for v_part in select value from jsonb_array_elements(v_parts)
    loop
      if (v_part->>'part_index')::integer <> v_expected_index
         or (v_part->>'byte_offset')::bigint <> v_expected_offset then
        raise exception 'file parts must be contiguous and ordered' using errcode = '22023';
      end if;
      v_part_length := (v_part->>'byte_length')::integer;
      if v_part_length < 1 or v_part_length > 20971520 then
        raise exception 'invalid logical part length' using errcode = '22023';
      end if;

      insert into public.import_file_parts (
        file_id, import_id, user_id, part_index, byte_offset, byte_length,
        content_sha256, object_path
      ) values (
        v_file_id,
        v_import_id,
        v_user_id,
        v_expected_index,
        v_expected_offset,
        v_part_length,
        v_part->>'content_sha256',
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
     > (p_manifest->>'total_logical_bytes')::bigint then
    raise exception 'manifest page bytes exceed import total' using errcode = '22023';
  end if;
  if (p_manifest->>'total_file_count')::integer = jsonb_array_length(v_files)
     and v_page_bytes <> (p_manifest->>'total_logical_bytes')::bigint then
    raise exception 'total logical bytes do not match files' using errcode = '22023';
  end if;

  return public.import_api_snapshot(v_import_id);
exception
  when unique_violation then
    select id into v_import_id
    from public.import_runs
    where user_id = v_user_id
      and client_idempotency_key = (p_manifest->>'client_idempotency_key')::uuid;
    if v_import_id is null then
      raise;
    end if;
    return public.import_api_snapshot(v_import_id);
end;
$$;

create or replace function public.append_import_manifest_page(p_import_id uuid, p_page jsonb)
returns jsonb
language plpgsql
security invoker
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
  if v_user_id is null then
    raise exception 'authentication required' using errcode = '42501';
  end if;
  if jsonb_typeof(p_page) <> 'object' or jsonb_typeof(v_files) <> 'array'
     or jsonb_array_length(v_files) < 1 or jsonb_array_length(v_files) > 1000
     or v_page_index < 1 or v_page_hash !~ '^[0-9a-f]{64}$' then
    raise exception 'invalid manifest page' using errcode = '22023';
  end if;

  select state, total_file_count, total_logical_bytes
  into v_state, v_total_file_count, v_total_logical_bytes
  from public.import_runs
  where id = p_import_id and user_id = v_user_id
  for update;
  if v_state is null then
    raise exception 'import not found' using errcode = 'P0002';
  end if;
  if v_state <> 'uploading' then
    raise exception 'manifest pages require an uploading import' using errcode = '22023';
  end if;

  if exists (
    select 1 from public.import_manifest_pages
    where import_id = p_import_id and page_index = v_page_index and content_sha256 = v_page_hash
  ) then
    return public.import_api_snapshot(p_import_id);
  end if;
  if exists (
    select 1 from public.import_manifest_pages
    where import_id = p_import_id and (page_index = v_page_index or content_sha256 = v_page_hash)
  ) then
    raise exception 'manifest page conflicts with an existing page' using errcode = '23505';
  end if;

  select coalesce(max(page_index), -1) + 1 into v_expected_page_index
  from public.import_manifest_pages where import_id = p_import_id;
  if v_page_index <> v_expected_page_index then
    raise exception 'manifest pages must be appended in order' using errcode = '22023';
  end if;

  select count(*), coalesce(sum(logical_bytes), 0)
  into v_existing_file_count, v_existing_logical_bytes
  from public.import_files where import_id = p_import_id;
  select coalesce(sum((value->>'logical_bytes')::bigint), 0)
  into v_page_bytes from jsonb_array_elements(v_files);
  if v_existing_file_count + jsonb_array_length(v_files) > v_total_file_count
     or v_existing_logical_bytes + v_page_bytes > v_total_logical_bytes then
    raise exception 'manifest page exceeds declared import totals (existing_files=%, page_files=%, total_files=%, existing_bytes=%, page_bytes=%, total_bytes=%)',
      v_existing_file_count, jsonb_array_length(v_files), v_total_file_count,
      v_existing_logical_bytes, v_page_bytes, v_total_logical_bytes
      using errcode = '22023';
  end if;

  insert into public.import_manifest_pages (
    import_id, user_id, page_index, content_sha256, file_count, logical_bytes
  ) values (
    p_import_id, v_user_id, v_page_index, v_page_hash,
    jsonb_array_length(v_files), v_page_bytes
  );

  for v_file in select value from jsonb_array_elements(v_files)
  loop
    v_file_id := gen_random_uuid();
    v_file_bytes := (v_file->>'logical_bytes')::bigint;
    v_inclusion_state := coalesce(v_file->>'inclusion_state', 'planned');
    if v_inclusion_state not in ('planned', 'skipped_duplicate', 'excluded') then
      raise exception 'invalid initial file inclusion state' using errcode = '22023';
    end if;

    insert into public.import_files (
      id, import_id, user_id, client_file_id, source_reference_hash,
      source_family, content_kind, inclusion_state, logical_bytes, content_sha256
    ) values (
      v_file_id, p_import_id, v_user_id, (v_file->>'client_file_id')::uuid,
      v_file->>'source_reference_hash', v_file->>'source_family',
      v_file->>'content_kind', v_inclusion_state, v_file_bytes,
      v_file->>'content_sha256'
    );

    v_parts := coalesce(v_file->'parts', '[]'::jsonb);
    if jsonb_typeof(v_parts) <> 'array' then
      raise exception 'file parts must be an array' using errcode = '22023';
    end if;
    if v_inclusion_state <> 'planned' and jsonb_array_length(v_parts) <> 0 then
      raise exception 'excluded or duplicate files cannot have upload parts' using errcode = '22023';
    end if;

    v_expected_index := 0;
    v_expected_offset := 0;
    for v_part in select value from jsonb_array_elements(v_parts)
    loop
      if (v_part->>'part_index')::integer <> v_expected_index
         or (v_part->>'byte_offset')::bigint <> v_expected_offset then
        raise exception 'file parts must be contiguous and ordered' using errcode = '22023';
      end if;
      v_part_length := (v_part->>'byte_length')::integer;
      if v_part_length < 1 or v_part_length > 20971520 then
        raise exception 'invalid logical part length' using errcode = '22023';
      end if;
      insert into public.import_file_parts (
        file_id, import_id, user_id, part_index, byte_offset, byte_length,
        content_sha256, object_path
      ) values (
        v_file_id, p_import_id, v_user_id, v_expected_index, v_expected_offset,
        v_part_length, v_part->>'content_sha256',
        format('imports/%s/%s/%s/part-%s', v_user_id, p_import_id, v_file_id, v_expected_index)
      );
      v_expected_index := v_expected_index + 1;
      v_expected_offset := v_expected_offset + v_part_length;
    end loop;
    if v_inclusion_state = 'planned' and v_expected_offset <> v_file_bytes then
      raise exception 'planned part lengths do not match logical file size' using errcode = '22023';
    end if;
  end loop;

  if v_existing_file_count + jsonb_array_length(v_files) = v_total_file_count
     and v_existing_logical_bytes + v_page_bytes <> v_total_logical_bytes then
    raise exception 'final manifest page does not match declared bytes' using errcode = '22023';
  end if;
  return public.import_api_snapshot(p_import_id);
end;
$$;

create or replace function public.complete_import(p_import_id uuid)
returns jsonb
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_user_id uuid := auth.uid();
  v_state text;
begin
  select state into v_state
  from public.import_runs
  where id = p_import_id and user_id = v_user_id
  for update;

  if v_state is null then
    raise exception 'import not found' using errcode = 'P0002';
  end if;
  if v_state in ('queued', 'processing', 'completed', 'completed_with_warnings') then
    return public.import_api_snapshot(p_import_id);
  end if;
  if v_state not in ('uploading', 'uploaded') then
    raise exception 'import cannot be completed from state %', v_state using errcode = '22023';
  end if;
  if exists (
    select 1
    from public.import_runs as run
    where run.id = p_import_id
      and (
        run.total_file_count <> (select count(*) from public.import_files where import_id = p_import_id)
        or run.total_logical_bytes <> (select coalesce(sum(logical_bytes), 0) from public.import_files where import_id = p_import_id)
      )
  ) or not exists (
    select 1 from public.import_files
    where import_id = p_import_id and user_id = v_user_id and inclusion_state = 'planned'
  ) then
    raise exception 'manifest is incomplete or has no planned files' using errcode = '22023';
  end if;
  if exists (
    select 1
    from public.import_file_parts as part
    left join storage.objects as object
      on object.bucket_id = 'health-imports'
     and object.name = part.object_path
    where part.import_id = p_import_id
      and part.user_id = v_user_id
      and (
        object.id is null
        or coalesce((object.metadata->>'size')::bigint, -1) <> part.byte_length
        or coalesce(object.user_metadata->>'contentSha256', '') <> part.content_sha256
      )
  ) then
    raise exception 'one or more upload parts are missing or invalid' using errcode = '22023';
  end if;

  update public.import_file_parts
  set state = 'verified', verified_at = now()
  where import_id = p_import_id and user_id = v_user_id;
  update public.import_files
  set inclusion_state = 'verified'
  where import_id = p_import_id and user_id = v_user_id and inclusion_state = 'planned';
  update public.import_runs
  set state = 'uploaded'
  where id = p_import_id and user_id = v_user_id;

  insert into public.import_jobs (import_id, user_id, job_type, state)
  values (p_import_id, v_user_id, 'parse_import', 'queued')
  on conflict (import_id, job_type) do nothing;

  update public.import_runs
  set state = 'queued'
  where id = p_import_id and user_id = v_user_id;

  return public.import_api_snapshot(p_import_id);
end;
$$;

create or replace function public.begin_import_delete(p_import_id uuid)
returns jsonb
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_user_id uuid := auth.uid();
begin
  if not exists (
    select 1 from public.import_runs where id = p_import_id and user_id = v_user_id
  ) then
    raise exception 'import not found' using errcode = 'P0002';
  end if;

  update public.import_jobs
  set state = 'cancelled'
  where import_id = p_import_id and user_id = v_user_id
    and state in ('queued', 'leased', 'processing');
  update public.import_runs
  set state = 'deleting'
  where id = p_import_id and user_id = v_user_id and state <> 'deleted';

  return jsonb_build_object(
    'id', p_import_id,
    'state', 'deleting',
    'object_paths', coalesce((
      select jsonb_agg(object_path order by object_path)
      from public.import_file_parts
      where import_id = p_import_id and user_id = v_user_id and state <> 'deleted'
    ), '[]'::jsonb)
  );
end;
$$;

create or replace function public.finish_import_delete(p_import_id uuid)
returns jsonb
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_user_id uuid := auth.uid();
begin
  update public.import_file_parts
  set state = 'deleted'
  where import_id = p_import_id and user_id = v_user_id;
  update public.import_files
  set inclusion_state = 'deleted'
  where import_id = p_import_id and user_id = v_user_id;
  update public.import_runs
  set state = 'deleted'
  where id = p_import_id and user_id = v_user_id;

  if not found then
    raise exception 'import not found' using errcode = 'P0002';
  end if;
  return public.import_api_snapshot(p_import_id);
end;
$$;

revoke all on function public.import_api_snapshot(uuid) from public, anon;
revoke all on function public.create_import_manifest(jsonb) from public, anon;
revoke all on function public.append_import_manifest_page(uuid, jsonb) from public, anon;
revoke all on function public.complete_import(uuid) from public, anon;
revoke all on function public.begin_import_delete(uuid) from public, anon;
revoke all on function public.finish_import_delete(uuid) from public, anon;

grant execute on function public.import_api_snapshot(uuid) to authenticated;
grant execute on function public.create_import_manifest(jsonb) to authenticated;
grant execute on function public.append_import_manifest_page(uuid, jsonb) to authenticated;
grant execute on function public.complete_import(uuid) to authenticated;
grant execute on function public.begin_import_delete(uuid) to authenticated;
grant execute on function public.finish_import_delete(uuid) to authenticated;
