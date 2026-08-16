BEGIN;
SELECT plan(149);

SELECT ok(to_regclass('public.import_runs') is not null, 'import_runs exists');
SELECT ok(to_regclass('public.import_manifest_pages') is not null, 'import_manifest_pages exists');
SELECT ok(to_regclass('public.import_files') is not null, 'import_files exists');
SELECT ok(to_regclass('public.import_file_parts') is not null, 'import_file_parts exists');
SELECT ok(to_regclass('public.import_jobs') is not null, 'import_jobs exists');
SELECT ok(to_regclass('public.import_errors') is not null, 'import_errors exists');
SELECT ok(to_regclass('public.health_samples') is not null, 'health_samples exists');
SELECT ok(to_regclass('public.normalization_provenance') is not null, 'normalization_provenance exists');
SELECT ok(to_regclass('public.legacy_xls_quality_reports') is not null, 'legacy XLS quality table exists');
SELECT ok(to_regclass('public.health_samples_owner_family_type_time_idx') is not null, 'health sample source precedence index exists');
SELECT ok(
  (select relrowsecurity from pg_class where oid = 'public.legacy_xls_quality_reports'::regclass),
  'legacy XLS quality table has RLS enabled'
);
SELECT ok(
  has_table_privilege('authenticated', 'public.legacy_xls_quality_reports', 'SELECT'),
  'owners can read legacy XLS quality through RLS'
);
SELECT ok(
  not has_table_privilege('authenticated', 'public.legacy_xls_quality_reports', 'INSERT')
  and not has_table_privilege('authenticated', 'public.legacy_xls_quality_reports', 'UPDATE')
  and not has_table_privilege('authenticated', 'public.legacy_xls_quality_reports', 'DELETE'),
  'clients cannot mutate legacy XLS quality'
);
SELECT ok(
  exists (select 1 from pg_constraint where conname = 'legacy_xls_quality_counts_nonnegative'),
  'legacy XLS quality counts are internally consistent'
);
SELECT ok(
  exists (select 1 from pg_trigger where tgname = 'health_sample_source_precedence' and not tgisinternal),
  'JSON-wins sample precedence trigger exists'
);
SELECT ok(
  to_regprocedure('public.worker_persist_legacy_xls_quality(uuid,uuid,uuid,integer,integer,integer,integer,integer,integer)') is not null,
  'lease-bound legacy XLS quality RPC exists'
);
SELECT ok(
  exists (
    select 1 from pg_attribute
    where attrelid = 'public.health_samples'::regclass
      and attname = 'canonical_day' and not attisdropped
  ),
  'health samples expose a canonical day for daily backfill precedence'
);
SELECT ok(to_regclass('public.sleep_sessions') is not null, 'sleep_sessions exists');
SELECT ok(to_regclass('public.sleep_stages') is not null, 'sleep_stages exists');
SELECT is(
  (SELECT count(*) FROM pg_class WHERE oid IN ('public.sleep_sessions'::regclass, 'public.sleep_stages'::regclass) AND relrowsecurity),
  2::bigint,
  'sleep tables have RLS enabled'
);
SELECT ok(exists (select 1 from pg_constraint where conname = 'sleep_sessions_owner_dedupe'), 'sleep sessions deduplicate per owner');
SELECT ok(exists (select 1 from pg_constraint where conname = 'sleep_stages_owner_dedupe'), 'sleep stages deduplicate per owner');
SELECT is(
  (select count(*) from information_schema.role_table_grants where grantee = 'authenticated' and table_schema = 'public' and table_name in ('sleep_sessions','sleep_stages') and privilege_type in ('INSERT','UPDATE','DELETE')),
  0::bigint,
  'authenticated users have no direct sleep writes'
);
SELECT ok(
  exists (select 1 from information_schema.columns where table_schema = 'public' and table_name = 'normalization_provenance' and column_name = 'source_unit'),
  'provenance retains the source unit code without raw payload retention'
);
SELECT ok(
  exists (select 1 from pg_constraint where conname = 'health_samples_unit_check'),
  'health sample canonical units are constrained'
);

SELECT is(
  (SELECT count(*) FROM pg_class WHERE oid IN (
    'public.health_samples'::regclass,
    'public.normalization_provenance'::regclass
  ) AND relrowsecurity),
  2::bigint,
  'normalization tables have RLS enabled'
);
SELECT ok(
  exists (select 1 from pg_constraint where conname = 'health_samples_owner_dedupe_key'),
  'health samples deduplicate per owner with a stable key'
);
SELECT is(
  (select count(*) from information_schema.role_table_grants
   where grantee = 'authenticated' and table_schema = 'public'
     and table_name in ('health_samples', 'normalization_provenance')
     and privilege_type in ('INSERT', 'UPDATE', 'DELETE')),
  0::bigint,
  'authenticated users have no direct normalization writes'
);

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
  6::bigint,
  'authenticated can read owner rows but cannot bypass RPC write transitions'
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
SELECT ok(
  has_function_privilege('authenticated', 'public.list_expired_imports(integer)', 'EXECUTE'),
  'authenticated can list only its own expired imports for cleanup'
);
SELECT ok(
  not has_function_privilege('anon', 'public.list_expired_imports(integer)', 'EXECUTE'),
  'anonymous callers cannot list expired imports'
);
SELECT is(
  (SELECT count(*)
   FROM pg_proc
   WHERE oid IN (
     'public.import_api_snapshot(uuid)'::regprocedure,
     'public.create_import_manifest(jsonb)'::regprocedure,
     'public.append_import_manifest_page(uuid,jsonb)'::regprocedure,
     'public.complete_import(uuid)'::regprocedure,
     'public.begin_import_delete(uuid)'::regprocedure,
     'public.finish_import_delete(uuid)'::regprocedure,
     'public.list_expired_imports(integer)'::regprocedure
   ) AND prosecdef),
  7::bigint,
  'all import RPCs use explicit caller checks behind definer write privileges'
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

INSERT INTO public.import_runs (id, user_id, client_idempotency_key, source_kind)
VALUES (
  '10000000-0000-4000-8000-000000000031',
  '00000000-0000-4000-8000-000000000031',
  '20000000-0000-4000-8000-000000000031',
  'directory'
);

INSERT INTO public.import_files (
  id, import_id, user_id, client_file_id, source_reference_hash, source_family,
  content_kind, inclusion_state, logical_bytes, content_sha256
) VALUES (
  '30000000-0000-4000-8000-000000000031',
  '10000000-0000-4000-8000-000000000031',
  '00000000-0000-4000-8000-000000000031',
  '40000000-0000-4000-8000-000000000031',
  'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
  'synthetic-json', 'application/json', 'verified', 1,
  'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb'
);
INSERT INTO public.import_files (
  id, import_id, user_id, client_file_id, source_reference_hash, source_family,
  content_kind, inclusion_state, logical_bytes, content_sha256
) VALUES (
  '30000000-0000-4000-8000-000000000032',
  '10000000-0000-4000-8000-000000000031',
  '00000000-0000-4000-8000-000000000031',
  '40000000-0000-4000-8000-000000000032',
  'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa32',
  'synthetic-json', 'application/json', 'planned', 1,
  'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb32'
);
INSERT INTO public.import_file_parts (
  id, file_id, import_id, user_id, part_index, byte_offset, byte_length,
  content_sha256, object_path, state
) VALUES (
  '35000000-0000-4000-8000-000000000031',
  '30000000-0000-4000-8000-000000000031',
  '10000000-0000-4000-8000-000000000031',
  '00000000-0000-4000-8000-000000000031',
  0, 0, 1,
  'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
  'imports/00000000-0000-4000-8000-000000000031/10000000-0000-4000-8000-000000000031/30000000-0000-4000-8000-000000000031/part-0',
  'verified'
);
INSERT INTO public.health_samples (
  user_id, import_id, import_file_id, dedupe_key, source_family, source_type,
  source_record_hash, started_at, ended_at, unit, value, parser_version
) VALUES (
  '00000000-0000-4000-8000-000000000031',
  '10000000-0000-4000-8000-000000000031',
  '30000000-0000-4000-8000-000000000031',
  'cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc',
  'huawei_health_json', 'steps',
  'dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd',
  '2026-01-02T00:00:00Z', '2026-01-02T00:01:00Z', 'count', 1, 'huawei-json-v1'
);
UPDATE public.import_runs
SET timezone_candidate = 'UTC'
WHERE id = '10000000-0000-4000-8000-000000000031';
INSERT INTO public.health_samples (
  user_id, import_id, import_file_id, dedupe_key, source_family, source_type,
  source_record_hash, started_at, ended_at, unit, value, parser_version
) VALUES (
  '00000000-0000-4000-8000-000000000031',
  '10000000-0000-4000-8000-000000000031',
  '30000000-0000-4000-8000-000000000031',
  repeat('7', 64), 'huawei_legacy_xls', 'steps', repeat('8', 64),
  '2026-01-02T00:00:00Z', '2026-01-03T00:00:00Z', 'count', 50, 'huawei-legacy-xls-v1'
);
SELECT is(
  (select count(*) from public.health_samples where dedupe_key = repeat('7', 64)),
  0::bigint,
  'legacy daily sample cannot override overlapping granular JSON'
);
INSERT INTO public.health_samples (
  user_id, import_id, import_file_id, dedupe_key, source_family, source_type,
  source_record_hash, started_at, ended_at, unit, value, parser_version
) VALUES (
  '00000000-0000-4000-8000-000000000031',
  '10000000-0000-4000-8000-000000000031',
  '30000000-0000-4000-8000-000000000031',
  repeat('9', 64), 'huawei_legacy_xls', 'steps', repeat('a', 64),
  '2026-01-03T00:00:00Z', '2026-01-04T00:00:00Z', 'count', 50, 'huawei-legacy-xls-v1'
);
SELECT is(
  (select count(*) from public.health_samples where dedupe_key = repeat('9', 64)),
  1::bigint,
  'legacy daily sample fills a missing metric day'
);
INSERT INTO public.health_samples (
  user_id, import_id, import_file_id, dedupe_key, source_family, source_type,
  source_record_hash, started_at, ended_at, unit, value, parser_version
) VALUES (
  '00000000-0000-4000-8000-000000000031',
  '10000000-0000-4000-8000-000000000031',
  '30000000-0000-4000-8000-000000000031',
  repeat('b', 64), 'huawei_health_json', 'steps', repeat('c', 64),
  '2026-01-03T12:00:00Z', '2026-01-03T12:01:00Z', 'count', 60, 'huawei-json-v1'
);
SELECT is(
  (select count(*) from public.health_samples where dedupe_key = repeat('9', 64)),
  0::bigint,
  'granular JSON imported later replaces lower-priority legacy data'
);
DELETE FROM public.health_samples WHERE dedupe_key = repeat('b', 64);
INSERT INTO public.legacy_xls_quality_reports (
  user_id, import_id, import_file_id, approved_sheet_count,
  excluded_sheet_count, unknown_sheet_count, covered_date_count,
  candidate_metric_count, inserted_metric_count, conflict_metric_count,
  ambiguous_cell_count
) VALUES (
  '00000000-0000-4000-8000-000000000031',
  '10000000-0000-4000-8000-000000000031',
  '30000000-0000-4000-8000-000000000031',
  1, 1, 1, 2, 5, 4, 1, 1
);
INSERT INTO public.import_jobs (id, import_id, user_id, state)
VALUES ('50000000-0000-4000-8000-000000000031', '10000000-0000-4000-8000-000000000031', '00000000-0000-4000-8000-000000000031', 'queued');

SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-000000000031', true);

SELECT is(
  (SELECT count(*) FROM public.import_runs WHERE id = '10000000-0000-4000-8000-000000000031'),
  1::bigint,
  'owner can create and read an import run'
);
SELECT is(
  (SELECT count(*) FROM public.health_samples WHERE import_id = '10000000-0000-4000-8000-000000000031'),
  1::bigint,
  'owner can read normalized samples'
);
SELECT is(
  (select count(*) from public.legacy_xls_quality_reports
   where import_id = '10000000-0000-4000-8000-000000000031'),
  1::bigint,
  'owner can read legacy XLS quality counts'
);
SELECT throws_ok(
  $sql$delete from public.import_runs where id = '10000000-0000-4000-8000-000000000031'$sql$,
  '42501',
  'permission denied for table import_runs',
  'owner cannot bypass Storage-first cleanup with a direct metadata delete'
);

SET LOCAL request.jwt.claim.sub = '00000000-0000-4000-8000-000000000032';
SELECT is(
  (select count(*) from public.legacy_xls_quality_reports
   where import_id = '10000000-0000-4000-8000-000000000031'),
  0::bigint,
  'another owner cannot read legacy XLS quality counts'
);
SELECT is(
  (SELECT count(*) FROM public.import_runs WHERE id = '10000000-0000-4000-8000-000000000031'),
  0::bigint,
  'another authenticated user cannot read the owner import run'
);
SELECT is(
  (SELECT count(*) FROM public.health_samples WHERE import_id = '10000000-0000-4000-8000-000000000031'),
  0::bigint,
  'another authenticated user cannot read normalized samples'
);
SELECT throws_ok(
  $sql$delete from public.import_runs where id = '10000000-0000-4000-8000-000000000031'$sql$,
  '42501',
  'permission denied for table import_runs',
  'another user has no direct metadata write privilege'
);
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

RESET ROLE;
INSERT INTO public.health_samples (
  id, user_id, import_id, import_file_id, dedupe_key, source_family,
  source_type, source_record_hash, started_at, ended_at, unit, value,
  parser_version
)
SELECT
  '71000000-0000-4000-8000-000000000031',
  '00000000-0000-4000-8000-000000000031',
  current_setting('app.test_import_id')::uuid,
  file.id,
  repeat('1', 64),
  'huawei_health_json',
  'heart_rate',
  repeat('2', 64),
  '2026-01-02T00:00:00Z',
  '2026-01-02T00:01:00Z',
  'bpm',
  72,
  'huawei-json-v1'
FROM public.import_files file
WHERE file.import_id = current_setting('app.test_import_id')::uuid;
INSERT INTO public.normalization_provenance (
  id, user_id, import_id, import_file_id, source_family,
  source_record_hash, parser_version, timezone_resolution
)
SELECT
  '72000000-0000-4000-8000-000000000031',
  '00000000-0000-4000-8000-000000000031',
  current_setting('app.test_import_id')::uuid,
  file.id,
  'huawei_health_json',
  repeat('2', 64),
  'huawei-json-v1',
  'explicit_offset'
FROM public.import_files file
WHERE file.import_id = current_setting('app.test_import_id')::uuid;
INSERT INTO public.sleep_sessions (
  id, user_id, import_id, import_file_id, dedupe_key, source_record_hash,
  started_at, ended_at, duration_seconds, parser_version
)
SELECT
  '73000000-0000-4000-8000-000000000031',
  '00000000-0000-4000-8000-000000000031',
  current_setting('app.test_import_id')::uuid,
  file.id,
  repeat('3', 64),
  repeat('4', 64),
  '2026-01-02T00:00:00Z',
  '2026-01-02T01:00:00Z',
  3600,
  'huawei-json-v1'
FROM public.import_files file
WHERE file.import_id = current_setting('app.test_import_id')::uuid;
INSERT INTO public.sleep_stages (
  id, user_id, sleep_session_id, dedupe_key, stage_code, started_at, ended_at
) VALUES (
  '74000000-0000-4000-8000-000000000031',
  '00000000-0000-4000-8000-000000000031',
  '73000000-0000-4000-8000-000000000031',
  repeat('5', 64),
  'deep',
  '2026-01-02T00:00:00Z',
  '2026-01-02T01:00:00Z'
);
INSERT INTO public.activities (
  id, user_id, import_id, import_file_id, dedupe_key, source_record_hash,
  activity_type, started_at, ended_at, duration_seconds, parser_version
)
SELECT
  '75000000-0000-4000-8000-000000000031',
  '00000000-0000-4000-8000-000000000031',
  current_setting('app.test_import_id')::uuid,
  file.id,
  repeat('6', 64),
  repeat('7', 64),
  'walking',
  '2026-01-02T00:00:00Z',
  '2026-01-02T00:10:00Z',
  600,
  'huawei-json-v1'
FROM public.import_files file
WHERE file.import_id = current_setting('app.test_import_id')::uuid;
INSERT INTO public.workout_sessions (
  id, user_id, import_id, import_file_id, dedupe_key, source_record_hash,
  workout_type, started_at, ended_at, duration_seconds, parser_version
)
SELECT
  '76000000-0000-4000-8000-000000000031',
  '00000000-0000-4000-8000-000000000031',
  current_setting('app.test_import_id')::uuid,
  file.id,
  repeat('8', 64),
  repeat('9', 64),
  'running',
  '2026-01-02T00:00:00Z',
  '2026-01-02T00:30:00Z',
  1800,
  'huawei-json-v1'
FROM public.import_files file
WHERE file.import_id = current_setting('app.test_import_id')::uuid;
INSERT INTO public.import_jobs (
  id, import_id, user_id, state, lease_generation, parser_version
) VALUES (
  '77000000-0000-4000-8000-000000000031',
  current_setting('app.test_import_id')::uuid,
  '00000000-0000-4000-8000-000000000031',
  'queued',
  '79000000-0000-4000-8000-000000000031',
  'huawei-json-v1'
);
INSERT INTO public.parser_file_checkpoints (
  id, job_id, import_id, import_file_id, user_id, part_index, byte_offset,
  batch_sequence, parser_version, lease_generation, normalized_record_count
)
SELECT
  '78000000-0000-4000-8000-000000000031',
  '77000000-0000-4000-8000-000000000031',
  current_setting('app.test_import_id')::uuid,
  file.id,
  '00000000-0000-4000-8000-000000000031',
  0,
  1,
  0,
  'huawei-json-v1',
  '79000000-0000-4000-8000-000000000031',
  1
FROM public.import_files file
WHERE file.import_id = current_setting('app.test_import_id')::uuid;
INSERT INTO public.parser_file_completions (
  job_id, import_id, import_file_id, user_id, normalized_record_count
)
SELECT
  '77000000-0000-4000-8000-000000000031',
  current_setting('app.test_import_id')::uuid,
  file.id,
  '00000000-0000-4000-8000-000000000031',
  1
FROM public.import_files file
WHERE file.import_id = current_setting('app.test_import_id')::uuid;
INSERT INTO public.import_errors (
  id, import_id, user_id, code, retryable
) VALUES (
  '7a000000-0000-4000-8000-000000000031',
  current_setting('app.test_import_id')::uuid,
  '00000000-0000-4000-8000-000000000031',
  'source_object_unavailable',
  true
);
SAVEPOINT storage_guard_test;
INSERT INTO storage.objects (bucket_id, name, owner_id)
SELECT
  'health-imports',
  part.object_path,
  part.user_id::text
FROM public.import_file_parts part
WHERE part.import_id = current_setting('app.test_import_id')::uuid;

SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claim.sub = '00000000-0000-4000-8000-000000000031';
SELECT throws_ok(
  format(
    'select public.finish_import_delete(%L::uuid)',
    current_setting('app.test_import_id')
  ),
  'P0001',
  'storage_objects_remain',
  'owner cannot finalize deletion while a private source object remains'
);
ROLLBACK TO SAVEPOINT storage_guard_test;
RELEASE SAVEPOINT storage_guard_test;
RESET ROLE;

SET LOCAL ROLE authenticated;
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
RESET ROLE;
SELECT is(
  (
    select count(*)
    from (
      select 1 from public.health_samples where import_id = current_setting('app.test_import_id')::uuid
      union all
      select 1 from public.normalization_provenance where import_id = current_setting('app.test_import_id')::uuid
      union all
      select 1 from public.sleep_sessions where import_id = current_setting('app.test_import_id')::uuid
      union all
      select 1 from public.sleep_stages where sleep_session_id = '73000000-0000-4000-8000-000000000031'
      union all
      select 1 from public.activities where import_id = current_setting('app.test_import_id')::uuid
      union all
      select 1 from public.workout_sessions where import_id = current_setting('app.test_import_id')::uuid
    ) retained
  ),
  0::bigint,
  'owner import deletion purges all canonical and provenance rows'
);
SELECT is(
  (
    select count(*)
    from (
      select 1 from public.import_manifest_pages where import_id = current_setting('app.test_import_id')::uuid
      union all
      select 1 from public.import_files where import_id = current_setting('app.test_import_id')::uuid
      union all
      select 1 from public.import_file_parts where import_id = current_setting('app.test_import_id')::uuid
      union all
      select 1 from public.import_jobs where import_id = current_setting('app.test_import_id')::uuid
      union all
      select 1 from public.import_errors where import_id = current_setting('app.test_import_id')::uuid
      union all
      select 1 from public.parser_file_checkpoints where import_id = current_setting('app.test_import_id')::uuid
      union all
      select 1 from public.parser_file_completions where import_id = current_setting('app.test_import_id')::uuid
    ) retained
  ),
  0::bigint,
  'owner import deletion purges source, error, job, and checkpoint metadata'
);
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claim.sub = '00000000-0000-4000-8000-000000000031';

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
INSERT INTO public.import_runs (id, user_id, client_idempotency_key, source_kind, state, cleanup_after)
VALUES
  ('10000000-0000-4000-8000-000000000051', '00000000-0000-4000-8000-000000000031', '20000000-0000-4000-8000-000000000051', 'zip', 'uploading', now() - interval '1 minute'),
  ('10000000-0000-4000-8000-000000000052', '00000000-0000-4000-8000-000000000031', '20000000-0000-4000-8000-000000000052', 'zip', 'uploading', now() + interval '1 hour'),
  ('10000000-0000-4000-8000-000000000053', '00000000-0000-4000-8000-000000000031', '20000000-0000-4000-8000-000000000053', 'zip', 'completed', now() - interval '1 minute');
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claim.sub = '00000000-0000-4000-8000-000000000031';
SELECT is(
  (SELECT count(*) FROM public.list_expired_imports(25)),
  1::bigint,
  'cleanup list includes only expired imports in a cleanable state'
);
SELECT is(
  (SELECT import_id FROM public.list_expired_imports(25)),
  '10000000-0000-4000-8000-000000000051'::uuid,
  'cleanup list returns the expected owner import'
);
SET LOCAL request.jwt.claim.sub = '00000000-0000-4000-8000-000000000032';
SELECT is(
  (SELECT count(*) FROM public.list_expired_imports(25)),
  0::bigint,
  'another user cannot discover the owner expired import'
);
SELECT ok(to_regclass('public.activities') is not null, 'activities exists');
SELECT ok((SELECT relrowsecurity FROM pg_class WHERE oid = 'public.activities'::regclass), 'activities has RLS');
SELECT ok(exists (select 1 from pg_constraint where conname = 'activities_owner_dedupe'), 'activities deduplicate per owner');
SELECT ok(to_regclass('public.workout_sessions') is not null, 'workout_sessions exists');
SELECT ok((SELECT relrowsecurity FROM pg_class WHERE oid = 'public.workout_sessions'::regclass), 'workout sessions have RLS');
SELECT ok(exists (select 1 from pg_constraint where conname = 'workout_sessions_owner_dedupe'), 'workout sessions deduplicate per owner');
SELECT ok(exists (select 1 from information_schema.columns where table_schema = 'public' and table_name = 'import_runs' and column_name = 'raw_parts_recovery_until'), 'imports record the raw-part recovery deadline');
SELECT ok(exists (select 1 from information_schema.columns where table_schema = 'public' and table_name = 'import_jobs' and column_name = 'lease_generation'), 'jobs record lease generations');
SELECT ok(to_regclass('public.parser_file_checkpoints') is not null, 'parser checkpoints exist');
SELECT ok((SELECT relrowsecurity FROM pg_class WHERE oid = 'public.parser_file_checkpoints'::regclass), 'parser checkpoints have RLS');
SELECT ok(to_regclass('public.parser_file_completions') is not null, 'parser file completions exist');
SELECT ok((SELECT relrowsecurity FROM pg_class WHERE oid = 'public.parser_file_completions'::regclass), 'parser file completions have RLS');
SELECT is(
  (select count(*) from information_schema.role_table_grants
   where grantee = 'authenticated' and table_schema = 'public'
     and table_name = 'parser_file_completions' and privilege_type <> 'SELECT'),
  0::bigint,
  'owners cannot directly mutate parser file completions'
);
SELECT ok(exists (select 1 from pg_constraint where conname = 'parser_file_checkpoints_batch_key'), 'checkpoints deduplicate by job and batch');
SELECT ok(exists (select 1 from pg_constraint where conname = 'parser_file_checkpoints_job_fk'), 'checkpoints remain bound to the leased job owner');
SELECT is(
  (select count(*) from information_schema.role_table_grants where grantee = 'authenticated' and table_schema = 'public' and table_name = 'parser_file_checkpoints' and privilege_type in ('INSERT','UPDATE','DELETE')),
  0::bigint,
  'owners cannot directly mutate parser checkpoints'
);
SELECT ok(to_regprocedure('public.worker_claim_import_job(text,integer)') is not null, 'worker claim RPC exists');
SELECT ok(to_regprocedure('public.worker_renew_import_job(uuid,uuid,integer)') is not null, 'worker renew RPC exists');
SELECT ok(to_regprocedure('public.worker_checkpoint_import_job(uuid,uuid,uuid,uuid,integer,bigint,integer,bigint,text[])') is not null, 'worker checkpoint RPC exists');
SELECT ok(to_regprocedure('public.worker_finish_import_job(uuid,uuid,text,text[])') is not null, 'worker finish RPC exists');
SELECT ok(to_regprocedure('public.list_worker_raw_cleanup_candidates(integer)') is not null, 'worker cleanup candidate RPC exists');
SELECT ok(not has_function_privilege('anon', 'public.worker_claim_import_job(text,integer)', 'EXECUTE'), 'anonymous callers cannot claim jobs');
SELECT ok(has_function_privilege('authenticated', 'public.worker_claim_import_job(text,integer)', 'EXECUTE'), 'authenticated role can invoke claim after worker claim validation');
SELECT is(
  (select count(*) from pg_proc where oid in (
    'public.worker_claim_import_job(text,integer)'::regprocedure,
    'public.worker_renew_import_job(uuid,uuid,integer)'::regprocedure,
    'public.worker_checkpoint_import_job(uuid,uuid,uuid,uuid,integer,bigint,integer,bigint,text[])'::regprocedure,
    'public.worker_finish_import_job(uuid,uuid,text,text[])'::regprocedure,
    'public.list_worker_raw_cleanup_candidates(integer)'::regprocedure,
    'public.worker_import_source(uuid,uuid)'::regprocedure,
    'public.worker_persist_normalized_batch(uuid,uuid,uuid,integer,jsonb,text[])'::regprocedure
  ) and prosecdef),
  7::bigint,
  'worker transitions use definer functions with internal claim checks'
);
SELECT ok(exists (select 1 from information_schema.columns where table_schema = 'public' and table_name = 'import_jobs' and column_name = 'processed_file_count'), 'jobs expose safe file progress counts');
SELECT ok(exists (select 1 from information_schema.columns where table_schema = 'public' and table_name = 'import_jobs' and column_name = 'warning_codes'), 'jobs expose stable warning codes only');
SELECT ok(exists (select 1 from pg_constraint where conname = 'import_jobs_max_attempts_check'), 'jobs bound retry attempts');
SELECT ok(exists (select 1 from pg_indexes where schemaname = 'public' and indexname = 'import_runs_raw_parts_recovery_idx'), 'raw cleanup has a bounded recovery index');
SELECT ok(exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'parser_file_checkpoints' and policyname = 'Parser checkpoints are readable by owner'), 'checkpoint reads are owner-scoped');
SELECT ok(to_regprocedure('public.worker_import_source(uuid,uuid)') is not null, 'worker source RPC exists');
SELECT ok(to_regprocedure('public.worker_persist_normalized_batch(uuid,uuid,uuid,integer,jsonb,text[])') is not null, 'worker canonical persistence RPC exists');
SELECT is(
  (select count(*) from pg_proc where oid in (
    'public.worker_complete_import_file(uuid,uuid,uuid,bigint,text[])'::regprocedure,
    'public.worker_retry_import_job(uuid,uuid,text)'::regprocedure,
    'public.worker_raw_cleanup_source(integer)'::regprocedure,
    'public.worker_finish_raw_cleanup(uuid)'::regprocedure,
    'public.worker_has_cleanup_import_object(text,text)'::regprocedure
  )),
  5::bigint,
  'worker file completion, retry, and raw cleanup RPCs exist'
);
SELECT ok(
  not has_function_privilege('anon', 'public.worker_complete_import_file(uuid,uuid,uuid,bigint,text[])', 'EXECUTE'),
  'anonymous callers cannot complete worker files'
);
SELECT ok(exists (select 1 from pg_policies where schemaname = 'storage' and tablename = 'objects' and policyname = 'Active worker can read leased private import parts'), 'private Storage reads require an active worker lease');
SELECT ok(
  exists (
    select 1 from pg_policies
    where schemaname = 'storage' and tablename = 'objects'
      and policyname = 'Recovery-expired worker can select private import parts'
  ),
  'recovery-expired source rows are visible only for Storage delete evaluation'
);
SELECT ok(
  exists (
    select 1 from pg_policies
    where schemaname = 'storage' and tablename = 'objects'
      and policyname = 'Recovery-expired worker can delete private import parts'
  ),
  'private source deletion requires the expired recovery window'
);
SELECT is(
  (select count(*) from information_schema.role_table_grants
   where grantee = 'anon' and table_schema = 'public'
     and table_name in (
       'health_samples', 'normalization_provenance', 'sleep_sessions',
       'sleep_stages', 'activities', 'workout_sessions',
       'parser_file_checkpoints'
     )),
  0::bigint,
  'anonymous callers have no Step 4 canonical table grants'
);
SELECT is(
  (select count(*) from information_schema.role_table_grants
   where grantee = 'authenticated' and table_schema = 'public'
     and table_name in (
       'health_samples', 'normalization_provenance', 'sleep_sessions',
       'sleep_stages', 'activities', 'workout_sessions',
       'parser_file_checkpoints'
     )
     and privilege_type <> 'SELECT'),
  0::bigint,
  'authenticated callers can only read Step 4 canonical tables'
);
SELECT ok(
  not has_function_privilege(
    'anon',
    'public.worker_has_active_import_object(text,text)',
    'EXECUTE'
  ),
  'anonymous callers cannot execute the leased Storage helper'
);
SELECT ok(
  has_function_privilege(
    'authenticated',
    'public.worker_has_active_import_object(text,text)',
    'EXECUTE'
  ),
  'signed-in Storage policy evaluation can execute the leased object helper'
);
SELECT ok(not has_function_privilege('anon', 'public.worker_persist_normalized_batch(uuid,uuid,uuid,integer,jsonb,text[])', 'EXECUTE'), 'anonymous callers cannot persist canonical batches');
SELECT ok(has_function_privilege('authenticated', 'public.worker_persist_normalized_batch(uuid,uuid,uuid,integer,jsonb,text[])', 'EXECUTE'), 'authenticated role reaches persistence only after worker claim validation');
SET LOCAL request.jwt.claims = '{"sub":"00000000-0000-4000-8000-000000000031"}';
SELECT throws_ok(
  $sql$select * from public.worker_claim_import_job('huawei-json-v1', 60)$sql$,
  'P0001', 'worker_configuration_invalid',
  'browser-shaped claims cannot claim a worker job'
);
SET LOCAL request.jwt.claims = '{"sub":"00000000-0000-4000-8000-000000000031","app_metadata":{"import_worker":"true"}}';
SET LOCAL request.jwt.claim.sub = '00000000-0000-4000-8000-000000000031';
SELECT is((SELECT count(*) FROM public.worker_claim_import_job('huawei-json-v1', 60)), 1::bigint, 'dedicated worker claim leases one queued job');
SELECT ok((SELECT lease_generation IS NOT NULL FROM public.import_jobs WHERE id = '50000000-0000-4000-8000-000000000031'), 'claim assigns a lease generation');
SELECT is((SELECT state FROM public.import_jobs WHERE id = '50000000-0000-4000-8000-000000000031'), 'processing', 'claim moves the job to processing');
SELECT set_config('app.worker_generation', (SELECT lease_generation::text FROM public.import_jobs WHERE id = '50000000-0000-4000-8000-000000000031'), true);
SELECT ok(public.worker_renew_import_job('50000000-0000-4000-8000-000000000031', current_setting('app.worker_generation')::uuid, 60), 'worker can renew its active lease');
SELECT is(
  (select count(*) from public.worker_import_source(
    '50000000-0000-4000-8000-000000000031',
    current_setting('app.worker_generation')::uuid
  )),
  1::bigint,
  'worker source includes verified upload files'
);
SELECT is(
  jsonb_array_length((
    select parts from public.worker_import_source(
      '50000000-0000-4000-8000-000000000031',
      current_setting('app.worker_generation')::uuid
    )
  )),
  1,
  'worker source exposes immutable part metadata for the leased file'
);
SELECT throws_ok(
  $sql$
    select public.worker_persist_normalized_batch(
      '50000000-0000-4000-8000-000000000031',
      current_setting('app.worker_generation')::uuid,
      '30000000-0000-4000-8000-000000000032',
      0,
      '[]'::jsonb,
      '{}'::text[]
    )
  $sql$,
  'P0001',
  'source_file_invalid',
  'worker persistence rejects a file that was not verified'
);
SELECT throws_ok(
  $sql$
    select public.worker_persist_normalized_batch(
      '50000000-0000-4000-8000-000000000031',
      current_setting('app.worker_generation')::uuid,
      '30000000-0000-4000-8000-000000000031',
      0,
      '[{"kind":"sample","raw":"excluded"}]'::jsonb,
      '{}'::text[]
    )
  $sql$,
  'P0001',
  'canonical_record_invalid',
  'worker persistence rejects raw or sensitive canonical fields'
);
SELECT ok(
  public.worker_persist_normalized_batch(
    '50000000-0000-4000-8000-000000000031',
    current_setting('app.worker_generation')::uuid,
    '30000000-0000-4000-8000-000000000031',
    0,
    $batch$
      [
        {
          "kind":"sample",
          "dedupe_key":"eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee",
          "source_family":"huawei_health_json",
          "source_type":"heart_rate",
          "source_record_hash":"ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff",
          "started_at":"2026-01-02T00:00:00Z",
          "ended_at":"2026-01-02T00:01:00Z",
          "unit":"bpm",
          "source_unit":"bpm",
          "value":72,
          "parser_version":"huawei-json-v1"
        },
        {
          "kind":"activity",
          "dedupe_key":"abababababababababababababababababababababababababababababababab",
          "source_record_hash":"cdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcd",
          "activity_type":"walking",
          "started_at":"2026-01-02T01:00:00Z",
          "ended_at":"2026-01-02T01:10:00Z",
          "duration_seconds":600,
          "parser_version":"huawei-json-v1"
        }
      ]
    $batch$::jsonb,
    ARRAY['route_content_dropped']
  ),
  'worker persists one bounded canonical batch'
);
SELECT ok(
  (SELECT count(*) FROM public.parser_file_checkpoints WHERE job_id = '50000000-0000-4000-8000-000000000031') = 1
  and
  (SELECT count(*) FROM public.health_samples WHERE dedupe_key = repeat('e', 64)) = 1
  and
  (SELECT count(*) FROM public.activities WHERE dedupe_key = repeat('ab', 32)) = 1,
  'canonical persistence and its checkpoint commit together'
);
SELECT throws_ok(
  $sql$
    select public.worker_persist_normalized_batch(
      '50000000-0000-4000-8000-000000000031',
      current_setting('app.worker_generation')::uuid,
      '30000000-0000-4000-8000-000000000031',
      0,
      '[]'::jsonb,
      ARRAY['route_content_dropped']
    )
  $sql$,
  'P0001',
  'checkpoint_replay_mismatch',
  'checkpoint replay rejects a different committed batch shape'
);
SELECT ok(
  public.worker_persist_normalized_batch(
    '50000000-0000-4000-8000-000000000031',
    current_setting('app.worker_generation')::uuid,
    '30000000-0000-4000-8000-000000000031',
    0,
    $batch$
      [
        {
          "kind":"sample",
          "dedupe_key":"eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee",
          "source_family":"huawei_health_json",
          "source_type":"heart_rate",
          "source_record_hash":"ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff",
          "started_at":"2026-01-02T00:00:00Z",
          "ended_at":"2026-01-02T00:01:00Z",
          "unit":"bpm",
          "source_unit":"bpm",
          "value":72,
          "parser_version":"huawei-json-v1"
        },
        {
          "kind":"activity",
          "dedupe_key":"abababababababababababababababababababababababababababababababab",
          "source_record_hash":"cdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcd",
          "activity_type":"walking",
          "started_at":"2026-01-02T01:00:00Z",
          "ended_at":"2026-01-02T01:10:00Z",
          "duration_seconds":600,
          "parser_version":"huawei-json-v1"
        }
      ]
    $batch$::jsonb,
    ARRAY['route_content_dropped']
  )
  and (SELECT count(*) FROM public.parser_file_checkpoints WHERE job_id = '50000000-0000-4000-8000-000000000031') = 1
  and (SELECT count(*) FROM public.health_samples WHERE dedupe_key = repeat('e', 64)) = 1
  and (SELECT count(*) FROM public.activities WHERE dedupe_key = repeat('ab', 32)) = 1,
  'exact batch replay is idempotent across canonical rows and checkpoints'
);
SELECT ok(
  public.worker_complete_import_file(
    '50000000-0000-4000-8000-000000000031',
    current_setting('app.worker_generation')::uuid,
    '30000000-0000-4000-8000-000000000031',
    2,
    ARRAY['route_content_dropped']
  ),
  'worker records one completed source file'
);
SELECT is(
  (select processed_file_count from public.import_jobs where id = '50000000-0000-4000-8000-000000000031'),
  1,
  'file completion increments owner-visible progress once'
);
SELECT ok(
  public.worker_complete_import_file(
    '50000000-0000-4000-8000-000000000031',
    current_setting('app.worker_generation')::uuid,
    '30000000-0000-4000-8000-000000000031',
    2,
    ARRAY['route_content_dropped']
  )
  and (select count(*) from public.parser_file_completions where job_id = '50000000-0000-4000-8000-000000000031') = 1,
  'file completion replay is idempotent'
);
SELECT is(
  public.worker_renew_import_job('50000000-0000-4000-8000-000000000031', '60000000-0000-4000-8000-000000000031'::uuid, 60),
  false,
  'stale lease generation cannot renew a job'
);
SELECT ok(public.worker_finish_import_job('50000000-0000-4000-8000-000000000031', current_setting('app.worker_generation')::uuid, 'completed_with_warnings', ARRAY['route_content_dropped']), 'worker completion is idempotent and warning-safe');
SELECT is((SELECT state FROM public.import_runs WHERE id = '10000000-0000-4000-8000-000000000031'), 'completed_with_warnings', 'completion updates the owner import state');
SELECT ok((SELECT raw_parts_recovery_until >= now() + interval '23 hours' FROM public.import_runs WHERE id = '10000000-0000-4000-8000-000000000031'), 'completion applies the 24-hour raw recovery window');

RESET ROLE;
INSERT INTO public.import_runs (
  id, user_id, client_idempotency_key, source_kind, state
) VALUES (
  '10000000-0000-4000-8000-000000000061',
  '00000000-0000-4000-8000-000000000031',
  '20000000-0000-4000-8000-000000000061',
  'directory', 'processing'
);
INSERT INTO public.import_files (
  id, import_id, user_id, client_file_id, source_reference_hash,
  source_family, content_kind, inclusion_state, logical_bytes, content_sha256
) VALUES (
  '30000000-0000-4000-8000-000000000061',
  '10000000-0000-4000-8000-000000000061',
  '00000000-0000-4000-8000-000000000031',
  '40000000-0000-4000-8000-000000000061',
  'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa61',
  'synthetic-json', 'application/json', 'verified', 1,
  'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb61'
);
INSERT INTO public.import_file_parts (
  id, file_id, import_id, user_id, part_index, byte_offset, byte_length,
  content_sha256, object_path, state
) VALUES (
  '35000000-0000-4000-8000-000000000061',
  '30000000-0000-4000-8000-000000000061',
  '10000000-0000-4000-8000-000000000061',
  '00000000-0000-4000-8000-000000000031',
  0, 0, 1,
  'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb61',
  'imports/00000000-0000-4000-8000-000000000031/10000000-0000-4000-8000-000000000061/30000000-0000-4000-8000-000000000061/part-0',
  'verified'
);
INSERT INTO public.import_jobs (
  id, import_id, user_id, state, attempt_count, max_attempts,
  worker_subject, lease_generation, lease_expires_at
) VALUES (
  '50000000-0000-4000-8000-000000000061',
  '10000000-0000-4000-8000-000000000061',
  '00000000-0000-4000-8000-000000000031',
  'processing', 1, 3,
  '00000000-0000-4000-8000-000000000031',
  '60000000-0000-4000-8000-000000000061',
  now() + interval '5 minutes'
);

SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims = '{"sub":"00000000-0000-4000-8000-000000000031","app_metadata":{"import_worker":"true"}}';
SET LOCAL request.jwt.claim.sub = '00000000-0000-4000-8000-000000000031';
SELECT is(
  public.worker_retry_import_job(
    '50000000-0000-4000-8000-000000000061',
    '60000000-0000-4000-8000-000000000061',
    'source_part_unavailable'
  ),
  'queued',
  'retryable worker failure returns the job to the queue'
);
SELECT is(
  (select state from public.import_jobs where id = '50000000-0000-4000-8000-000000000061'),
  'queued',
  'retry clears the active lease without losing the job'
);

RESET ROLE;
UPDATE public.import_jobs
set state = 'processing',
    attempt_count = 3,
    worker_subject = '00000000-0000-4000-8000-000000000031',
    lease_generation = '60000000-0000-4000-8000-000000000062',
    lease_expires_at = now() + interval '5 minutes'
where id = '50000000-0000-4000-8000-000000000061';
UPDATE public.import_runs set state = 'processing'
where id = '10000000-0000-4000-8000-000000000061';

SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims = '{"sub":"00000000-0000-4000-8000-000000000031","app_metadata":{"import_worker":"true"}}';
SET LOCAL request.jwt.claim.sub = '00000000-0000-4000-8000-000000000031';
SELECT is(
  public.worker_retry_import_job(
    '50000000-0000-4000-8000-000000000061',
    '60000000-0000-4000-8000-000000000062',
    'source_part_unavailable'
  ),
  'failed',
  'retry exhaustion moves the job to its terminal state'
);
SELECT ok(
  (select raw_parts_recovery_until >= now() + interval '23 hours'
   from public.import_runs where id = '10000000-0000-4000-8000-000000000061'),
  'retry exhaustion preserves the 24-hour recovery window'
);

RESET ROLE;
UPDATE public.import_runs
set raw_parts_recovery_until = now() - interval '1 minute'
where id = '10000000-0000-4000-8000-000000000061';

SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims = '{"sub":"00000000-0000-4000-8000-000000000031","app_metadata":{"import_worker":"true"}}';
SET LOCAL request.jwt.claim.sub = '00000000-0000-4000-8000-000000000031';
SELECT is(
  (select count(*) from public.worker_raw_cleanup_source(25)
   where import_id = '10000000-0000-4000-8000-000000000061'),
  1::bigint,
  'recovery-expired terminal import becomes a cleanup candidate'
);
SELECT is(
  (select cardinality(object_paths) from public.worker_raw_cleanup_source(25)
   where import_id = '10000000-0000-4000-8000-000000000061'),
  1,
  'cleanup candidate contains only its immutable source object paths'
);
SELECT ok(
  public.worker_has_cleanup_import_object(
    'health-imports',
    'imports/00000000-0000-4000-8000-000000000031/10000000-0000-4000-8000-000000000061/30000000-0000-4000-8000-000000000061/part-0'
  ),
  'worker delete policy admits only an expired candidate path'
);
SELECT ok(
  public.worker_finish_raw_cleanup('10000000-0000-4000-8000-000000000061'),
  'worker finalizes raw cleanup after Storage is empty'
);
SELECT ok(
  (select raw_parts_recovery_until is null
     from public.import_runs where id = '10000000-0000-4000-8000-000000000061')
  and
  (select state = 'deleted'
     from public.import_file_parts where id = '35000000-0000-4000-8000-000000000061'),
  'cleanup clears the recovery deadline and marks source metadata deleted'
);
RESET ROLE;

SELECT * FROM finish();
ROLLBACK;

