-- An owner-facing import delete is a privacy boundary, not only a raw-source
-- cleanup. The import run remains as a deletion tombstone for an idempotent API
-- response, so explicitly purge every Step 4 canonical row before finalizing
-- the tombstone.

create or replace function public.finish_import_delete(p_import_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := auth.uid();
begin
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

  update public.import_file_parts
  set state = 'deleted'
  where import_id = p_import_id and user_id = v_user_id;
  update public.import_files
  set inclusion_state = 'deleted'
  where import_id = p_import_id and user_id = v_user_id;
  update public.import_runs
  set state = 'deleted',
      raw_parts_recovery_until = null,
      updated_at = now()
  where id = p_import_id and user_id = v_user_id;

  if not found then
    raise exception 'import not found' using errcode = 'P0002';
  end if;
  return public.import_api_snapshot(p_import_id);
end;
$$;

revoke all on function public.finish_import_delete(uuid)
  from public, anon, authenticated;
grant execute on function public.finish_import_delete(uuid)
  to authenticated;
