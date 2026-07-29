-- Supabase Storage evaluates DELETE through a SELECT-visible row set. Keep
-- recovery cleanup narrowly scoped to the same expired, terminal import object
-- predicate used by the worker's DELETE policy.

create policy "Recovery-expired worker can select private import parts"
  on storage.objects for select to authenticated
  using (
    bucket_id = 'health-imports'
    and public.worker_has_cleanup_import_object(bucket_id, name)
  );
