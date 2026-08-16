BEGIN;
SELECT plan(8);

SELECT ok(to_regclass('public.wellness_score_snapshots') is not null, 'score snapshot table exists');
SELECT ok(
  (select relrowsecurity from pg_class where oid = 'public.wellness_score_snapshots'::regclass),
  'score snapshot table has RLS enabled'
);
SELECT is(
  (select count(*) from pg_policies where schemaname = 'public' and tablename = 'wellness_score_snapshots'),
  2::bigint,
  'score snapshots have owner read and insert policies'
);
SELECT ok(
  has_table_privilege('authenticated', 'public.wellness_score_snapshots', 'SELECT')
  and has_table_privilege('authenticated', 'public.wellness_score_snapshots', 'INSERT')
  and not has_table_privilege('authenticated', 'public.wellness_score_snapshots', 'UPDATE')
  and not has_table_privilege('authenticated', 'public.wellness_score_snapshots', 'DELETE'),
  'authenticated users can only read and insert score snapshots'
);
SELECT ok(not has_table_privilege('anon', 'public.wellness_score_snapshots', 'SELECT'), 'anonymous users cannot read score snapshots');

INSERT INTO auth.users (
  id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) VALUES
  ('00000000-0000-4000-8000-000000000081', 'authenticated', 'authenticated', 'step7-owner-a@example.test', '', now(), '{"provider":"email"}'::jsonb, '{}'::jsonb, now(), now()),
  ('00000000-0000-4000-8000-000000000082', 'authenticated', 'authenticated', 'step7-owner-b@example.test', '', now(), '{"provider":"email"}'::jsonb, '{}'::jsonb, now(), now());

SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claim.sub = '00000000-0000-4000-8000-000000000081';
INSERT INTO public.wellness_score_snapshots (
  user_id, score_version, start_date, end_date, timezone, total_score,
  coverage_percent, components, trend, suggestions, source
) VALUES (
  '00000000-0000-4000-8000-000000000081', 'score-v1', '2026-01-01', '2026-01-28', 'UTC', 82.5,
  100, '[{"key":"sleep","score":82.5}]'::jsonb, '{"status":"stable"}'::jsonb,
  '[]'::jsonb, '{"kind":"get_wellness_report","range_days":28}'::jsonb
);
SELECT is((select count(*) from public.wellness_score_snapshots), 1::bigint, 'owner can insert a score snapshot');
SELECT throws_ok(
  $sql$update public.wellness_score_snapshots set total_score = 99 where user_id = '00000000-0000-4000-8000-000000000081'$sql$,
  '42501',
  NULL,
  'score snapshots cannot be updated by authenticated users'
);

SET LOCAL request.jwt.claim.sub = '00000000-0000-4000-8000-000000000082';
SELECT is((select count(*) from public.wellness_score_snapshots), 0::bigint, 'another user cannot read score snapshots');

SELECT * FROM finish();
ROLLBACK;
