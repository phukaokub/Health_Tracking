-- User-scoped reconciliation for stale foreground uploads. This deliberately
-- uses the caller's JWT/RLS boundary; a system-wide worker remains a separate
-- Step 4 credential decision.

create or replace function public.list_expired_imports(p_limit integer default 25)
returns table(import_id uuid)
language sql
stable
security invoker
set search_path = ''
as $$
  select run.id
  from public.import_runs as run
  where run.user_id = auth.uid()
    and run.cleanup_after <= now()
    and run.state in ('draft', 'uploading', 'uploaded', 'failed', 'cancelling', 'cancelled', 'deleting')
  order by run.cleanup_after, run.id
  limit least(greatest(coalesce(p_limit, 25), 1), 100)
$$;

revoke all on function public.list_expired_imports(integer) from public, anon;
grant execute on function public.list_expired_imports(integer) to authenticated;
