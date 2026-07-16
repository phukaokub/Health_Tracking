BEGIN;
SELECT plan(38);

SELECT ok(to_regclass('public.import_runs') is not null, 'import_runs exists');
SELECT ok(to_regclass('public.import_manifest_pages') is not null, 'import_manifest_pages exists');
SELECT ok(to_regclass('public.import_files') is not null, 'import_files exists');
SELECT ok(to_regclass('public.import_file_parts') is not null, 'import_file_parts exists');
SELECT ok(to_regclass('public.import_jobs') is not null, 'import_jobs exists');
SELECT ok(to_regclass('public.import_errors') is not null, 'import_errors exists');

SELECT is(
  (SELECT count(*) FROM pg_class WHERE oid IN (
    'public.import_runs'::regclass,
    'public.import_manifest_pages'::regclass,
    'public.import_files'::regclass,
    'public.import_file_parts'::regclass,
    'public.import_jobs'::regclass,
    'public.import_errors'::regclass
  ) AND relrowsecurity),
  6::bigint,
  'all import metadata tables have RLS enabled'
);

SELECT is(
  (SELECT count(*) FROM information_schema.role_table_grants
   WHERE grantee = 'authenticated'
     AND table_schema = 'public'
     AND table_name IN ('import_runs', 'import_manifest_pages', 'import_files', 'import_file_parts', 'import_jobs', 'import_errors')
     AND privilege_type IN ('SELECT', 'INSERT', 'UPDATE', 'DELETE')),
  24::bigint,
  'authenticated has explicit CRUD grants for all import metadata tables'
);

SELECT is(
  (SELECT count(*) FROM pg_policies
   WHERE schemaname = 'public'
     AND tablename IN ('import_runs', 'import_manifest_pages', 'import_files', 'import_file_parts', 'import_jobs', 'import_errors')),
  24::bigint,
  'all import metadata tables have owner CRUD policies'
);

SELECT ok(
  EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'import_files_run_owner_fk'
  ),
  'files cannot have an owner different from their import run'
);
SELECT ok(
  EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'import_file_parts_file_owner_fk'
  ),
  'parts cannot have an owner or import different from their file'
);
SELECT ok(
  EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'import_jobs_run_owner_fk'
  ),
  'jobs cannot have an owner different from their import run'
);
SELECT ok(
  EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'import_runs_idempotency_key'
  ),
  'import creation is idempotent per owner'
);
SELECT ok(
  EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'import_jobs_initial_job_key'
  ),
  'an import can have only one initial parser job'
);
SELECT ok(
  EXISTS (
    SELECT 1 FROM storage.buckets
    WHERE id = 'health-imports' AND public = false AND file_size_limit = 20971520
  ),
  'health-imports is private and caps one logical object at 20 MiB'
);
SELECT is(
  (SELECT count(*) FROM pg_policies
   WHERE schemaname = 'storage'
     AND tablename = 'objects'
     AND policyname IN (
       'Import objects are insertable by owner',
       'Import objects are readable by owner',
       'Import objects are deletable by owner'
     )),
  3::bigint,
  'private import Storage has owner insert, read, and delete policies only'
);

SELECT is(
  array_length(storage.foldername(
    'imports/00000000-0000-4000-8000-000000000031/10000000-0000-4000-8000-000000000031/20000000-0000-4000-8000-000000000031/part-0'
  ), 1),
  4,
  'immutable import object paths have four folder segments'
);
SELECT ok(
  has_function_privilege('authenticated', 'public.create_import_manifest(jsonb)', 'EXECUTE'),
  'authenticated can execute the invoker manifest function'
);
SELECT ok(
  not has_function_privilege('anon', 'public.create_import_manifest(jsonb)', 'EXECUTE'),
  'anonymous callers cannot execute the manifest function'
);
SELECT ok(
  has_function_privilege('authenticated', 'public.append_import_manifest_page(uuid, jsonb)', 'EXECUTE'),
  'authenticated can execute the invoker manifest page function'
);

INSERT INTO auth.users (
  id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) VALUES
  (
    '00000000-0000-4000-8000-000000000031', 'authenticated', 'authenticated',
    'step3-owner-a@example.test', '', now(),
    '{"provider":"email","providers":["email"]}'::jsonb, '{}'::jsonb, now(), now()
  ),
  (
    '00000000-0000-4000-8000-000000000032', 'authenticated', 'authenticated',
    'step3-owner-b@example.test', '', now(),
    '{"provider":"email","providers":["email"]}'::jsonb, '{}'::jsonb, now(), now()
  );

SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-000000000031', true);
INSERT INTO public.import_runs (id, user_id, client_idempotency_key, source_kind)
VALUES (
  '10000000-0000-4000-8000-000000000031',
  '00000000-0000-4000-8000-000000000031',
  '20000000-0000-4000-8000-000000000031',
  'directory'
);

SELECT is(
  (SELECT count(*) FROM public.import_runs WHERE id = '10000000-0000-4000-8000-000000000031'),
  1::bigint,
  'owner can create and read an import run'
);

SET LOCAL request.jwt.claim.sub = '00000000-0000-4000-8000-000000000032';
SELECT is(
  (SELECT count(*) FROM public.import_runs WHERE id = '10000000-0000-4000-8000-000000000031'),
  0::bigint,
  'another authenticated user cannot read the owner import run'
);
DELETE FROM public.import_runs WHERE id = '10000000-0000-4000-8000-000000000031';
RESET ROLE;

SELECT ok(
  EXISTS (SELECT 1 FROM public.import_runs WHERE id = '10000000-0000-4000-8000-000000000031'),
  'another authenticated user cannot delete the owner import run'
);

SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claim.sub = '00000000-0000-4000-8000-000000000031';
SELECT is(
  public.create_import_manifest($manifest$
    {
      "manifest_version": 1,
      "source_kind": "directory",
      "client_idempotency_key": "30000000-0000-4000-8000-000000000031",
      "timezone_candidate": "Asia/Bangkok",
      "total_file_count": 1,
      "total_logical_bytes": 1,
      "page_content_sha256": "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      "files": [{
        "client_file_id": "40000000-0000-4000-8000-000000000031",
        "source_reference_hash": "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
        "source_family": "synthetic-json",
        "content_kind": "application/json",
        "inclusion_state": "planned",
        "logical_bytes": 1,
        "content_sha256": "cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc",
        "parts": [{
          "part_index": 0,
          "byte_offset": 0,
          "byte_length": 1,
          "content_sha256": "dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd"
        }]
      }]
    }
  $manifest$::jsonb)->>'state',
  'uploading',
  'manifest RPC creates an uploading import'
);
SELECT is(
  (public.create_import_manifest($manifest$
    {
      "manifest_version": 1,
      "source_kind": "directory",
      "client_idempotency_key": "30000000-0000-4000-8000-000000000031",
      "timezone_candidate": "Asia/Bangkok",
      "total_file_count": 1,
      "total_logical_bytes": 1,
      "page_content_sha256": "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      "files": [{
        "client_file_id": "40000000-0000-4000-8000-000000000031",
        "source_reference_hash": "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
        "source_family": "synthetic-json",
        "content_kind": "application/json",
        "inclusion_state": "planned",
        "logical_bytes": 1,
        "content_sha256": "cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc",
        "parts": [{
          "part_index": 0,
          "byte_offset": 0,
          "byte_length": 1,
          "content_sha256": "dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd"
        }]
      }]
    }
  $manifest$::jsonb)->>'id')::uuid,
  (SELECT id FROM public.import_runs WHERE client_idempotency_key = '30000000-0000-4000-8000-000000000031'),
  'repeated manifest creation returns the same import'
);
SELECT is(
  (SELECT count(*) FROM public.import_runs WHERE client_idempotency_key = '30000000-0000-4000-8000-000000000031'),
  1::bigint,
  'idempotent manifest creation persists one run'
);
SELECT throws_ok(
  $sql$select public.create_import_manifest('{
    "manifest_version":1,
    "source_kind":"directory",
    "client_idempotency_key":"30000000-0000-4000-8000-000000000031",
    "total_file_count":1,
    "total_logical_bytes":2,
    "page_content_sha256":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
    "files":[]
  }'::jsonb)$sql$,
  'HT409',
  'idempotency key is already bound to another manifest',
  'reusing an idempotency key with different totals is rejected'
);
SELECT matches(
  (SELECT object_path FROM public.import_file_parts WHERE user_id = '00000000-0000-4000-8000-000000000031' ORDER BY created_at DESC LIMIT 1),
  '^imports/00000000-0000-4000-8000-000000000031/[0-9a-f-]{36}/[0-9a-f-]{36}/part-0$',
  'manifest RPC derives the immutable owner-scoped object path'
);
SELECT set_config(
  'app.test_import_id',
  (SELECT id::text FROM public.import_runs WHERE client_idempotency_key = '30000000-0000-4000-8000-000000000031'),
  true
);
SELECT throws_ok(
  format(
    'select public.complete_import(%L::uuid)',
    current_setting('app.test_import_id')
  ),
  '22023',
  'one or more upload parts are missing or invalid',
  'completion rejects missing Storage objects'
);

SET LOCAL request.jwt.claim.sub = '00000000-0000-4000-8000-000000000032';
SELECT is(
  public.import_api_snapshot(current_setting('app.test_import_id')::uuid),
  NULL::jsonb,
  'another user cannot read the manifest snapshot'
);
SELECT throws_ok(
  format(
    'select public.begin_import_delete(%L::uuid)',
    current_setting('app.test_import_id')
  ),
  'P0002',
  'import not found',
  'another user cannot begin import deletion'
);

SET LOCAL request.jwt.claim.sub = '00000000-0000-4000-8000-000000000031';
SELECT is(
  public.begin_import_delete(current_setting('app.test_import_id')::uuid)->>'state',
  'deleting',
  'owner can begin idempotent import cleanup'
);
SELECT is(
  public.finish_import_delete(current_setting('app.test_import_id')::uuid)->>'state',
  'deleted',
  'owner can finish import cleanup after Storage deletion'
);

SELECT is(
  jsonb_array_length(public.create_import_manifest($manifest$
    {
      "manifest_version": 1,
      "source_kind": "directory",
      "client_idempotency_key": "30000000-0000-4000-8000-000000000041",
      "total_file_count": 2,
      "total_logical_bytes": 2,
      "page_content_sha256": "eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee",
      "files": [{
        "client_file_id": "40000000-0000-4000-8000-000000000041",
        "source_reference_hash": "ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff",
        "source_family": "synthetic-json",
        "content_kind": "application/json",
        "inclusion_state": "planned",
        "logical_bytes": 1,
        "content_sha256": "1111111111111111111111111111111111111111111111111111111111111111",
        "parts": [{"part_index":0,"byte_offset":0,"byte_length":1,"content_sha256":"2222222222222222222222222222222222222222222222222222222222222222"}]
      }]
    }
  $manifest$::jsonb)->'files'),
  1,
  'first manifest page can declare a larger bounded import'
);
SELECT set_config(
  'app.paged_import_id',
  (SELECT id::text FROM public.import_runs WHERE client_idempotency_key = '30000000-0000-4000-8000-000000000041'),
  true
);
SELECT is(
  jsonb_array_length(public.append_import_manifest_page(
    current_setting('app.paged_import_id')::uuid,
    $page${
      "page_index":1,
      "page_content_sha256":"3333333333333333333333333333333333333333333333333333333333333333",
      "files":[{
        "client_file_id":"40000000-0000-4000-8000-000000000042",
        "source_reference_hash":"4444444444444444444444444444444444444444444444444444444444444444",
        "source_family":"synthetic-json",
        "content_kind":"application/json",
        "inclusion_state":"planned",
        "logical_bytes":1,
        "content_sha256":"5555555555555555555555555555555555555555555555555555555555555555",
        "parts":[{"part_index":0,"byte_offset":0,"byte_length":1,"content_sha256":"6666666666666666666666666666666666666666666666666666666666666666"}]
      }]
    }$page$::jsonb
  )->'files'),
  2,
  'ordered follow-up page completes the manifest metadata'
);
SELECT is(
  (SELECT count(*) FROM public.import_manifest_pages WHERE import_id = current_setting('app.paged_import_id')::uuid),
  2::bigint,
  'append created exactly the expected two manifest pages'
);
SELECT is(
  jsonb_array_length(public.append_import_manifest_page(
    current_setting('app.paged_import_id')::uuid,
    $page${
      "page_index":1,
      "page_content_sha256":"3333333333333333333333333333333333333333333333333333333333333333",
      "files":[{
        "client_file_id":"40000000-0000-4000-8000-000000000042",
        "source_reference_hash":"4444444444444444444444444444444444444444444444444444444444444444",
        "source_family":"synthetic-json",
        "content_kind":"application/json",
        "inclusion_state":"planned",
        "logical_bytes":1,
        "content_sha256":"5555555555555555555555555555555555555555555555555555555555555555",
        "parts":[{"part_index":0,"byte_offset":0,"byte_length":1,"content_sha256":"6666666666666666666666666666666666666666666666666666666666666666"}]
      }]
    }$page$::jsonb
  )->'files'),
  2,
  'repeated manifest page returns the existing snapshot without duplicates'
);
SELECT throws_ok(
  format(
    'select public.append_import_manifest_page(%L::uuid, %L::jsonb)',
    current_setting('app.paged_import_id'),
    '{"page_index":3,"page_content_sha256":"7777777777777777777777777777777777777777777777777777777777777777","files":[{"client_file_id":"40000000-0000-4000-8000-000000000043","source_reference_hash":"8888888888888888888888888888888888888888888888888888888888888888","source_family":"synthetic-json","content_kind":"application/json","inclusion_state":"excluded","logical_bytes":0,"content_sha256":"9999999999999999999999999999999999999999999999999999999999999999","parts":[]}]}'
  ),
  '22023',
  'manifest pages must be appended in order',
  'out-of-order manifest page is rejected'
);
RESET ROLE;

SELECT * FROM finish();
ROLLBACK;
