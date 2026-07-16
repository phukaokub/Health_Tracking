BEGIN;
SELECT plan(19);

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

SELECT * FROM finish();
ROLLBACK;
