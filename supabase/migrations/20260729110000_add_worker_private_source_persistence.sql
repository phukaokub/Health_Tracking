-- Step 4: lease-bound private Storage reads and canonical persistence. Raw
-- source data stays in private Storage; this migration exposes only immutable
-- part metadata to the dedicated worker and accepts only approved canonical
-- record shapes. ECG/RRI and GPS/route payloads have no accepted record kind.

alter table public.normalization_provenance
  add constraint normalization_provenance_owner_file_source_version_key
  unique (user_id, import_file_id, source_record_hash, parser_version);

create or replace function public.worker_has_active_import_object(p_bucket_id text, p_object_name text)
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
      join public.import_files file on file.id = part.file_id
      join public.import_jobs job on job.import_id = file.import_id and job.user_id = file.user_id
      where p_bucket_id = 'health-imports'
        and part.object_path = p_object_name
        and job.state = 'processing'
        and job.lease_expires_at >= now()
        and job.worker_subject = (select auth.jwt() ->> 'sub')
    );
$$;

grant execute on function public.worker_has_active_import_object(text, text) to authenticated;

create policy "Active worker can read leased private import parts"
on storage.objects for select to authenticated
using (bucket_id = 'health-imports' and public.worker_has_active_import_object(bucket_id, name));

create or replace function public.worker_import_source(p_job_id uuid, p_lease_generation uuid)
returns table(id uuid, logical_bytes bigint, content_sha256 text, parts jsonb)
language plpgsql
security definer
set search_path = ''
as $$
declare v_subject text := (select auth.jwt() ->> 'sub');
begin
  if coalesce((select auth.jwt() -> 'app_metadata' ->> 'import_worker'), '') <> 'true' or v_subject is null then
    raise exception using errcode = 'P0001', message = 'worker_configuration_invalid';
  end if;
  if not exists (select 1 from public.import_jobs job where job.id=p_job_id and job.worker_subject=v_subject and job.lease_generation=p_lease_generation and job.state='processing' and job.lease_expires_at>=now()) then
    raise exception using errcode = 'P0001', message = 'lease_lost';
  end if;
  return query
    select file.id, file.logical_bytes, file.content_sha256,
      coalesce(jsonb_agg(jsonb_build_object('part_index',part.part_index,'byte_length',part.byte_length,'content_sha256',part.content_sha256,'object_path',part.object_path) order by part.part_index) filter (where part.id is not null), '[]'::jsonb)
    from public.import_files file
    join public.import_jobs job on job.import_id=file.import_id and job.user_id=file.user_id
    left join public.import_file_parts part on part.file_id=file.id
    where job.id=p_job_id and file.inclusion_state='included'
    group by file.id, file.logical_bytes, file.content_sha256
    order by file.id;
end;
$$;

create or replace function public.worker_persist_normalized_batch(
  p_job_id uuid, p_lease_generation uuid, p_import_file_id uuid,
  p_batch_sequence integer, p_records jsonb, p_warning_codes text[] default '{}'
) returns boolean
language plpgsql security definer set search_path = ''
as $$
declare v_subject text := (select auth.jwt() ->> 'sub'); v_job public.import_jobs; v_count integer; v_part_index integer;
begin
  if coalesce((select auth.jwt() -> 'app_metadata' ->> 'import_worker'), '') <> 'true'
     or v_subject is null or p_batch_sequence < 0 or jsonb_typeof(p_records) <> 'array'
     or jsonb_array_length(p_records) > 1000 or cardinality(p_warning_codes) > 32
     or exists (select 1 from unnest(coalesce(p_warning_codes,'{}'::text[])) c where c !~ '^[a-z0-9_]{3,80}$') then
    raise exception using errcode='P0001', message='worker_configuration_invalid';
  end if;
  select * into v_job from public.import_jobs job where job.id=p_job_id and job.worker_subject=v_subject and job.lease_generation=p_lease_generation and job.state='processing' and job.lease_expires_at>=now() for update;
  if not found then raise exception using errcode='P0001', message='lease_lost'; end if;
  if not exists (select 1 from public.import_files f where f.id=p_import_file_id and f.import_id=v_job.import_id and f.user_id=v_job.user_id) then raise exception using errcode='P0001', message='source_file_invalid'; end if;
  if exists (select 1 from jsonb_array_elements(p_records) r where r->>'kind' not in ('sample','sleep_session','sleep_stage','activity','workout') or r ? 'raw' or r ? 'route' or r ? 'ecg' or r ? 'rri' or r ? 'gps') then raise exception using errcode='P0001', message='canonical_record_invalid'; end if;
  if exists (select 1 from public.parser_file_checkpoints c where c.job_id=p_job_id and c.batch_sequence>p_batch_sequence) then raise exception using errcode='P0001', message='checkpoint_out_of_order'; end if;
  if exists (select 1 from public.parser_file_checkpoints c where c.job_id=p_job_id and c.batch_sequence=p_batch_sequence) then return true; end if;

  insert into public.health_samples(user_id,import_id,import_file_id,dedupe_key,source_family,source_type,source_record_hash,started_at,ended_at,unit,value,parser_version)
  select v_job.user_id,v_job.import_id,p_import_file_id,r->>'dedupe_key',r->>'source_family',r->>'source_type',r->>'source_record_hash',(r->>'started_at')::timestamptz,(r->>'ended_at')::timestamptz,r->>'unit',(r->>'value')::numeric,r->>'parser_version'
  from jsonb_array_elements(p_records) r where r->>'kind'='sample' on conflict (user_id,dedupe_key) do nothing;
  insert into public.normalization_provenance(user_id,import_id,import_file_id,source_family,source_record_hash,parser_version,source_unit,timezone_resolution)
  select v_job.user_id,v_job.import_id,p_import_file_id,r->>'source_family',r->>'source_record_hash',r->>'parser_version',r->>'source_unit','explicit_offset'
  from jsonb_array_elements(p_records) r where r->>'kind'='sample' on conflict do nothing;
  insert into public.sleep_sessions(user_id,import_id,import_file_id,dedupe_key,source_record_hash,started_at,ended_at,duration_seconds,parser_version)
  select v_job.user_id,v_job.import_id,p_import_file_id,r->>'dedupe_key',r->>'source_record_hash',(r->>'started_at')::timestamptz,(r->>'ended_at')::timestamptz,(r->>'duration_seconds')::integer,r->>'parser_version' from jsonb_array_elements(p_records) r where r->>'kind'='sleep_session' on conflict (user_id,dedupe_key) do nothing;
  insert into public.sleep_stages(user_id,sleep_session_id,dedupe_key,stage_code,started_at,ended_at)
  select v_job.user_id,s.id,r->>'dedupe_key',r->>'stage_code',(r->>'started_at')::timestamptz,(r->>'ended_at')::timestamptz from jsonb_array_elements(p_records) r join public.sleep_sessions s on s.user_id=v_job.user_id and s.dedupe_key=r->>'parent_dedupe_key' where r->>'kind'='sleep_stage' on conflict (user_id,dedupe_key) do nothing;
  insert into public.activities(user_id,import_id,import_file_id,dedupe_key,source_record_hash,activity_type,started_at,ended_at,duration_seconds,parser_version)
  select v_job.user_id,v_job.import_id,p_import_file_id,r->>'dedupe_key',r->>'source_record_hash',r->>'activity_type',(r->>'started_at')::timestamptz,(r->>'ended_at')::timestamptz,(r->>'duration_seconds')::integer,r->>'parser_version' from jsonb_array_elements(p_records) r where r->>'kind'='activity' on conflict (user_id,dedupe_key) do nothing;
  insert into public.workout_sessions(user_id,import_id,import_file_id,dedupe_key,source_record_hash,workout_type,started_at,ended_at,duration_seconds,distance_metres,energy_kilocalories,parser_version)
  select v_job.user_id,v_job.import_id,p_import_file_id,r->>'dedupe_key',r->>'source_record_hash',r->>'workout_type',(r->>'started_at')::timestamptz,(r->>'ended_at')::timestamptz,(r->>'duration_seconds')::integer,nullif(r->>'distance_metres','')::numeric,nullif(r->>'energy_kilocalories','')::numeric,r->>'parser_version' from jsonb_array_elements(p_records) r where r->>'kind'='workout' on conflict (user_id,dedupe_key) do nothing;
  select coalesce(max(part_index),0) into v_part_index from public.import_file_parts where file_id=p_import_file_id;
  v_count := jsonb_array_length(p_records);
  perform public.worker_checkpoint_import_job(p_job_id,v_job.import_id,p_import_file_id,p_lease_generation,v_part_index,0,p_batch_sequence,v_count,p_warning_codes);
  return true;
end;
$$;

revoke all on function public.worker_import_source(uuid,uuid) from public, anon, authenticated;
revoke all on function public.worker_persist_normalized_batch(uuid,uuid,uuid,integer,jsonb,text[]) from public, anon, authenticated;
grant execute on function public.worker_import_source(uuid,uuid) to authenticated;
grant execute on function public.worker_persist_normalized_batch(uuid,uuid,uuid,integer,jsonb,text[]) to authenticated;
