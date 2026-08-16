-- Resume a leased import from its durable batch boundary. Completed files are
-- not returned again, and the worker receives the next global sequence number
-- for the remaining file stream.

drop function public.worker_import_source(uuid, uuid);

create function public.worker_import_source(
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

revoke all on function public.worker_import_source(uuid, uuid) from public, anon, authenticated;
grant execute on function public.worker_import_source(uuid, uuid) to authenticated;

