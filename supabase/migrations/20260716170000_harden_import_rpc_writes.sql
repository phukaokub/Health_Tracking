-- Keep authenticated metadata reads owner-scoped through RLS, but force every
-- metadata mutation through the reviewed RPC transitions. Each definer RPC
-- already derives auth.uid(), uses an empty search_path, and predicates every
-- existing-row mutation by that caller ID.

revoke insert, update, delete, truncate, references, trigger
  on public.import_runs,
     public.import_manifest_pages,
     public.import_files,
     public.import_file_parts,
     public.import_jobs,
     public.import_errors
  from authenticated;

alter function public.import_api_snapshot(uuid) security definer;
alter function public.create_import_manifest(jsonb) security definer;
alter function public.append_import_manifest_page(uuid, jsonb) security definer;
alter function public.complete_import(uuid) security definer;
alter function public.begin_import_delete(uuid) security definer;
alter function public.finish_import_delete(uuid) security definer;
alter function public.list_expired_imports(integer) security definer;
