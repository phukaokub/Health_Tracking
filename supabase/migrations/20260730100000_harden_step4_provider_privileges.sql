-- Hosted Supabase projects can grant broad table privileges through provider
-- defaults. Keep all Step 4 canonical writes behind the reviewed worker RPCs,
-- regardless of those defaults, while preserving owner-scoped reads.
revoke all
  on public.health_samples,
     public.normalization_provenance,
     public.sleep_sessions,
     public.sleep_stages,
     public.activities,
     public.workout_sessions,
     public.parser_file_checkpoints
  from public, anon, authenticated;

grant select
  on public.health_samples,
     public.normalization_provenance,
     public.sleep_sessions,
     public.sleep_stages,
     public.activities,
     public.workout_sessions,
     public.parser_file_checkpoints
  to authenticated;

-- The Storage policy invokes this helper for signed-in callers, but anonymous
-- callers must not be able to expose it through the Data API.
revoke all
  on function public.worker_has_active_import_object(text, text)
  from public, anon, authenticated;

grant execute
  on function public.worker_has_active_import_object(text, text)
  to authenticated;
