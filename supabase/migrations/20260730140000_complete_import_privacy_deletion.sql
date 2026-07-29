-- Finish the Step 4 owner-deletion contract. The Storage object must already
-- be gone, then all normalized, provenance, worker-progress, error, and source
-- metadata is purged while the run remains as an idempotent deleted tombstone.

create index if not exists health_samples_import_owner_idx
  on public.health_samples (import_id, user_id);
create index if not exists normalization_provenance_import_owner_delete_idx
  on public.normalization_provenance (import_id, user_id);
create index if not exists sleep_sessions_import_owner_idx
  on public.sleep_sessions (import_id, user_id);
create index if not exists sleep_stages_session_idx
  on public.sleep_stages (sleep_session_id);
create index if not exists activities_import_owner_idx
  on public.activities (import_id, user_id);
create index if not exists workout_sessions_import_owner_idx
  on public.workout_sessions (import_id, user_id);
create index if not exists parser_file_checkpoints_job_owner_idx
  on public.parser_file_checkpoints (job_id, import_id, user_id);
create index if not exists parser_file_checkpoints_file_owner_idx
  on public.parser_file_checkpoints (import_file_id, import_id, user_id);
create index if not exists parser_file_completions_job_owner_idx
  on public.parser_file_completions (job_id, import_id, user_id);
create index if not exists parser_file_completions_file_owner_idx
  on public.parser_file_completions (import_file_id, import_id, user_id);

create or replace function public.finish_import_delete(p_import_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := auth.uid();
begin
  if v_user_id is null or not exists (
    select 1
    from public.import_runs run
    where run.id = p_import_id and run.user_id = v_user_id
  ) then
    raise exception 'import not found' using errcode = 'P0002';
  end if;
  if exists (
    select 1
    from public.import_file_parts part
    join storage.objects object
      on object.bucket_id = 'health-imports' and object.name = part.object_path
    where part.import_id = p_import_id and part.user_id = v_user_id
  ) then
    raise exception using errcode = 'P0001', message = 'storage_objects_remain';
  end if;

  delete from public.sleep_sessions
  where import_id = p_import_id and user_id = v_user_id;
  delete from public.health_samples
  where import_id = p_import_id and user_id = v_user_id;
  delete from public.normalization_provenance
  where import_id = p_import_id and user_id = v_user_id;
  delete from public.activities
  where import_id = p_import_id and user_id = v_user_id;
  delete from public.workout_sessions
  where import_id = p_import_id and user_id = v_user_id;
  delete from public.import_errors
  where import_id = p_import_id and user_id = v_user_id;
  delete from public.import_jobs
  where import_id = p_import_id and user_id = v_user_id;
  delete from public.import_manifest_pages
  where import_id = p_import_id and user_id = v_user_id;
  delete from public.import_files
  where import_id = p_import_id and user_id = v_user_id;

  update public.import_runs
  set state = 'deleted',
      raw_parts_recovery_until = null,
      updated_at = now()
  where id = p_import_id and user_id = v_user_id;

  return public.import_api_snapshot(p_import_id);
end;
$$;

revoke all on function public.finish_import_delete(uuid)
  from public, anon, authenticated;
grant execute on function public.finish_import_delete(uuid)
  to authenticated;
