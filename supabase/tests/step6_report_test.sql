BEGIN;
SELECT plan(16);

SELECT ok(to_regclass('public.goals') is not null, 'goals table exists');
SELECT ok(
  (select relrowsecurity from pg_class where oid = 'public.goals'::regclass),
  'goals table has RLS enabled'
);
SELECT is(
  (select count(*) from pg_policies where schemaname = 'public' and tablename = 'goals'),
  4::bigint,
  'goals have owner CRUD policies'
);
SELECT ok(
  has_table_privilege('authenticated', 'public.goals', 'SELECT')
  and has_table_privilege('authenticated', 'public.goals', 'INSERT')
  and has_table_privilege('authenticated', 'public.goals', 'UPDATE')
  and has_table_privilege('authenticated', 'public.goals', 'DELETE'),
  'authenticated users have goal CRUD grants guarded by RLS'
);
SELECT ok(
  to_regprocedure('public.get_wellness_report(date,date,text)') is not null,
  'bounded wellness report RPC exists'
);
SELECT ok(has_function_privilege('authenticated', 'public.get_wellness_report(date,date,text)', 'EXECUTE'), 'authenticated users can execute the report RPC');
SELECT ok(not has_function_privilege('anon', 'public.get_wellness_report(date,date,text)', 'EXECUTE'), 'anonymous users cannot execute the report RPC');
SELECT ok(
  exists (select 1 from pg_indexes where schemaname = 'public' and indexname = 'goals_one_active_per_metric_idx'),
  'one active goal per metric is enforced by a partial unique index'
);

INSERT INTO auth.users (
  id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) VALUES
  ('00000000-0000-4000-8000-000000000071', 'authenticated', 'authenticated', 'step6-owner-a@example.test', '', now(), '{"provider":"email"}'::jsonb, '{}'::jsonb, now(), now()),
  ('00000000-0000-4000-8000-000000000072', 'authenticated', 'authenticated', 'step6-owner-b@example.test', '', now(), '{"provider":"email"}'::jsonb, '{}'::jsonb, now(), now());

INSERT INTO public.import_runs (id, user_id, client_idempotency_key, source_kind, state, timezone_candidate)
VALUES ('10000000-0000-4000-8000-000000000071', '00000000-0000-4000-8000-000000000071', '20000000-0000-4000-8000-000000000071', 'directory', 'completed', 'UTC');
INSERT INTO public.import_files (
  id, import_id, user_id, client_file_id, source_reference_hash, source_family,
  content_kind, inclusion_state, logical_bytes, content_sha256
) VALUES (
  '30000000-0000-4000-8000-000000000071', '10000000-0000-4000-8000-000000000071', '00000000-0000-4000-8000-000000000071',
  '40000000-0000-4000-8000-000000000071', repeat('a', 64), 'huawei_health_json', 'application/json', 'verified', 1, repeat('b', 64)
);
INSERT INTO public.health_samples (
  user_id, import_id, import_file_id, dedupe_key, source_family, source_type,
  source_record_hash, started_at, ended_at, unit, value, parser_version
) VALUES (
  '00000000-0000-4000-8000-000000000071', '10000000-0000-4000-8000-000000000071', '30000000-0000-4000-8000-000000000071',
  repeat('c', 64), 'huawei_health_json', 'steps', repeat('d', 64), '2026-01-01T01:00:00Z', '2026-01-01T01:01:00Z', 'count', 1200, 'huawei-json-v1'
);
INSERT INTO public.sleep_sessions (
  user_id, import_id, import_file_id, dedupe_key, source_record_hash,
  started_at, ended_at, duration_seconds, parser_version
) VALUES (
  '00000000-0000-4000-8000-000000000071', '10000000-0000-4000-8000-000000000071', '30000000-0000-4000-8000-000000000071',
  repeat('e', 64), repeat('f', 64), '2025-12-31T22:00:00Z', '2026-01-01T06:00:00Z', 28800, 'huawei-json-v1'
);

SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claim.sub = '00000000-0000-4000-8000-000000000071';
SELECT is(
  public.get_wellness_report('2026-01-01', '2026-01-03', 'UTC')->>'timezone',
  'UTC',
  'report returns the requested valid timezone'
);
SELECT is(
  jsonb_array_length(public.get_wellness_report('2026-01-01', '2026-01-03', 'UTC')->'days'),
  3,
  'report returns one bounded row per requested day'
);
SELECT is(
  (public.get_wellness_report('2026-01-01', '2026-01-03', 'UTC')->'days'->0->>'steps')::numeric,
  1200::numeric,
  'report aggregates owner steps into the correct local day'
);
SELECT is(
  (public.get_wellness_report('2026-01-01', '2026-01-03', 'UTC')->'days'->0->>'sleep_hours')::numeric,
  8::numeric,
  'report groups a sleep session by its end date'
);
SELECT throws_ok(
  $sql$select public.get_wellness_report('2026-01-01', '2026-04-01', 'UTC')$sql$,
  '22023',
  'report_range_invalid',
  'report rejects windows longer than 90 days'
);
INSERT INTO public.goals (user_id, metric, target, unit, cadence)
VALUES ('00000000-0000-4000-8000-000000000071', 'steps', 8000, 'steps', 'daily');
SELECT is((select count(*) from public.goals where user_id = '00000000-0000-4000-8000-000000000071'), 1::bigint, 'owner can create a goal');

SET LOCAL request.jwt.claim.sub = '00000000-0000-4000-8000-000000000072';
SELECT is((select count(*) from public.goals where user_id = '00000000-0000-4000-8000-000000000071'), 0::bigint, 'another user cannot read the owner goal');
SELECT is((public.get_wellness_report('2026-01-01', '2026-01-03', 'UTC')->'all_time_coverage'->>'steps')::boolean, false, 'another user cannot see owner report coverage');

SELECT * FROM finish();
ROLLBACK;
