-- Step 5: narrow legacy BIFF8 backfill with JSON-wins precedence and
-- owner-visible, value-free quality counts.

alter table public.health_samples
  add column canonical_day date;

create index health_samples_owner_type_day_idx
  on public.health_samples (user_id, source_type, canonical_day)
  where canonical_day is not null;

alter table public.normalization_provenance
  drop constraint normalization_provenance_timezone_resolution;
alter table public.normalization_provenance
  add constraint normalization_provenance_timezone_resolution
  check (timezone_resolution in ('explicit_offset', 'profile_fallback', 'import_timezone'));

create table public.legacy_xls_quality_reports (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  import_id uuid not null,
  import_file_id uuid not null,
  approved_sheet_count integer not null,
  excluded_sheet_count integer not null,
  unknown_sheet_count integer not null,
  covered_date_count integer not null,
  candidate_metric_count integer not null,
  inserted_metric_count integer not null,
  conflict_metric_count integer not null,
  ambiguous_cell_count integer not null,
  parser_version text not null default 'huawei-legacy-xls-v1',
  created_at timestamptz not null default now(),
  constraint legacy_xls_quality_import_owner_fk foreign key (import_id, user_id)
    references public.import_runs(id, user_id) on delete cascade,
  constraint legacy_xls_quality_file_owner_fk foreign key (import_file_id, import_id, user_id)
    references public.import_files(id, import_id, user_id) on delete cascade,
  constraint legacy_xls_quality_file_unique unique (import_file_id),
  constraint legacy_xls_quality_counts_nonnegative check (
    approved_sheet_count >= 0 and excluded_sheet_count >= 0 and
    unknown_sheet_count >= 0 and covered_date_count >= 0 and
    candidate_metric_count >= 0 and inserted_metric_count >= 0 and
    conflict_metric_count >= 0 and ambiguous_cell_count >= 0 and
    inserted_metric_count + conflict_metric_count = candidate_metric_count
  ),
  constraint legacy_xls_quality_parser_version check
    (parser_version = 'huawei-legacy-xls-v1')
);

create index legacy_xls_quality_owner_import_idx
  on public.legacy_xls_quality_reports (user_id, import_id);
alter table public.legacy_xls_quality_reports enable row level security;
grant select on public.legacy_xls_quality_reports to authenticated;
revoke insert, update, delete on public.legacy_xls_quality_reports from anon, authenticated;
create policy "Legacy XLS quality is readable by owner"
  on public.legacy_xls_quality_reports for select to authenticated
  using ((select auth.uid()) = user_id);

create or replace function public.enforce_health_sample_source_precedence()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
  if new.source_family = 'huawei_legacy_xls' then
    if new.canonical_day is null then
      select (new.started_at at time zone run.timezone_candidate)::date
      into new.canonical_day
      from public.import_runs run
      where run.id = new.import_id and run.user_id = new.user_id;
    end if;
    if new.canonical_day is null or exists (
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
  return new;
end;
$$;

create trigger health_sample_source_precedence
before insert on public.health_samples
for each row execute function public.enforce_health_sample_source_precedence();

revoke all on function public.enforce_health_sample_source_precedence() from public, anon, authenticated;

create or replace function public.enforce_legacy_provenance_timezone()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
  if new.source_family = 'huawei_legacy_xls' then
    if not exists (
      select 1 from public.health_samples sample
      where sample.user_id = new.user_id
        and sample.import_file_id = new.import_file_id
        and sample.source_record_hash = new.source_record_hash
    ) then
      return null;
    end if;
    new.timezone_resolution := 'import_timezone';
  end if;
  return new;
end;
$$;
create trigger legacy_provenance_timezone
before insert on public.normalization_provenance
for each row execute function public.enforce_legacy_provenance_timezone();
revoke all on function public.enforce_legacy_provenance_timezone() from public, anon, authenticated;

drop function public.worker_import_source(uuid, uuid);
create function public.worker_import_source(
  p_job_id uuid,
  p_lease_generation uuid
)
returns table(
  id uuid, logical_bytes bigint, content_sha256 text, source_family text,
  content_kind text, timezone_candidate text, parts jsonb
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
      coalesce(jsonb_agg(jsonb_build_object(
        'part_index', part.part_index, 'byte_length', part.byte_length,
        'content_sha256', part.content_sha256, 'object_path', part.object_path
      ) order by part.part_index) filter (where part.id is not null), '[]'::jsonb)
    from public.import_files file
    join public.import_runs run on run.id = file.import_id and run.user_id = file.user_id
    join public.import_jobs job on job.import_id = file.import_id and job.user_id = file.user_id
    left join public.import_file_parts part on part.file_id = file.id
    where job.id = p_job_id and file.inclusion_state = 'verified'
    group by file.id, file.logical_bytes, file.content_sha256, file.source_family,
      file.content_kind, run.timezone_candidate
    order by file.id;
end;
$$;

create or replace function public.worker_persist_legacy_xls_quality(
  p_job_id uuid, p_lease_generation uuid, p_import_file_id uuid,
  p_approved_sheet_count integer, p_excluded_sheet_count integer,
  p_unknown_sheet_count integer, p_covered_date_count integer,
  p_candidate_metric_count integer, p_ambiguous_cell_count integer
)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_subject text := (select auth.jwt() ->> 'sub');
  v_job public.import_jobs;
  v_inserted integer;
begin
  if coalesce((select auth.jwt() -> 'app_metadata' ->> 'import_worker'), '') <> 'true'
    or v_subject is null or least(
      p_approved_sheet_count, p_excluded_sheet_count, p_unknown_sheet_count,
      p_covered_date_count, p_candidate_metric_count, p_ambiguous_cell_count
    ) < 0 then
    raise exception using errcode = 'P0001', message = 'worker_configuration_invalid';
  end if;
  select * into v_job from public.import_jobs job
  where job.id = p_job_id and job.worker_subject = v_subject
    and job.lease_generation = p_lease_generation
    and job.state = 'processing' and job.lease_expires_at >= now()
  for update;
  if not found or not exists (
    select 1 from public.import_files file
    where file.id = p_import_file_id and file.import_id = v_job.import_id
      and file.user_id = v_job.user_id and file.source_family = 'legacy-xls'
      and file.inclusion_state = 'verified'
  ) then
    raise exception using errcode = 'P0001', message = 'source_file_invalid';
  end if;
  select count(*) into v_inserted from public.health_samples
  where import_file_id = p_import_file_id and user_id = v_job.user_id
    and source_family = 'huawei_legacy_xls';
  if v_inserted > p_candidate_metric_count then
    raise exception using errcode = 'P0001', message = 'quality_count_invalid';
  end if;
  insert into public.legacy_xls_quality_reports (
    user_id, import_id, import_file_id, approved_sheet_count,
    excluded_sheet_count, unknown_sheet_count, covered_date_count,
    candidate_metric_count, inserted_metric_count, conflict_metric_count,
    ambiguous_cell_count
  ) values (
    v_job.user_id, v_job.import_id, p_import_file_id, p_approved_sheet_count,
    p_excluded_sheet_count, p_unknown_sheet_count, p_covered_date_count,
    p_candidate_metric_count, v_inserted, p_candidate_metric_count - v_inserted,
    p_ambiguous_cell_count
  )
  on conflict (import_file_id) do update set
    approved_sheet_count = excluded.approved_sheet_count,
    excluded_sheet_count = excluded.excluded_sheet_count,
    unknown_sheet_count = excluded.unknown_sheet_count,
    covered_date_count = excluded.covered_date_count,
    candidate_metric_count = excluded.candidate_metric_count,
    inserted_metric_count = excluded.inserted_metric_count,
    conflict_metric_count = excluded.conflict_metric_count,
    ambiguous_cell_count = excluded.ambiguous_cell_count;
  return true;
end;
$$;

revoke all on function public.worker_import_source(uuid, uuid) from public, anon, authenticated;
revoke all on function public.worker_persist_legacy_xls_quality(
  uuid, uuid, uuid, integer, integer, integer, integer, integer, integer
) from public, anon, authenticated;
grant execute on function public.worker_import_source(uuid, uuid) to authenticated;
grant execute on function public.worker_persist_legacy_xls_quality(
  uuid, uuid, uuid, integer, integer, integer, integer, integer, integer
) to authenticated;

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
      'processed_file_count', job.processed_file_count,
      'normalized_record_count', job.normalized_record_count,
      'warning_codes', job.warning_codes,
      'last_checkpoint_at', job.last_checkpoint_at
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
revoke all on function public.import_api_snapshot(uuid) from public, anon;
grant execute on function public.import_api_snapshot(uuid) to authenticated;
