-- Step 7: insert-only, owner-scoped score provenance.
-- Scores are recomputed by the server from the bounded report RPC before an
-- application row is inserted. No raw health payloads are stored here.

create table public.wellness_score_snapshots (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  score_version text not null,
  start_date date not null,
  end_date date not null,
  timezone text not null,
  total_score numeric,
  coverage_percent integer not null,
  components jsonb not null,
  trend jsonb not null,
  suggestions jsonb not null,
  source jsonb not null,
  created_at timestamptz not null default now(),
  constraint wellness_score_snapshots_window_check check (end_date >= start_date and end_date <= start_date + 27),
  constraint wellness_score_snapshots_total_check check (total_score is null or (total_score >= 0 and total_score <= 100)),
  constraint wellness_score_snapshots_coverage_check check (coverage_percent between 0 and 100),
  constraint wellness_score_snapshots_components_check check (jsonb_typeof(components) = 'array'),
  constraint wellness_score_snapshots_trend_check check (jsonb_typeof(trend) = 'object'),
  constraint wellness_score_snapshots_suggestions_check check (jsonb_typeof(suggestions) = 'array'),
  constraint wellness_score_snapshots_source_check check (jsonb_typeof(source) = 'object')
);

create index wellness_score_snapshots_owner_window_idx
  on public.wellness_score_snapshots (user_id, end_date desc, created_at desc);

alter table public.wellness_score_snapshots enable row level security;

revoke all on public.wellness_score_snapshots from anon;
grant select, insert on public.wellness_score_snapshots to authenticated;
revoke update, delete on public.wellness_score_snapshots from authenticated;

create policy "Score snapshots are readable by owner"
  on public.wellness_score_snapshots for select to authenticated
  using ((select auth.uid()) = user_id);

create policy "Score snapshots are insertable by owner"
  on public.wellness_score_snapshots for insert to authenticated
  with check ((select auth.uid()) = user_id);
