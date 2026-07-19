create table public.sleep_sessions (
 id uuid primary key default gen_random_uuid(), user_id uuid not null references auth.users(id) on delete cascade, import_id uuid not null, import_file_id uuid not null, dedupe_key text not null, source_record_hash text not null, started_at timestamptz not null, ended_at timestamptz not null, duration_seconds integer not null, parser_version text not null, created_at timestamptz not null default now(),
 constraint sleep_sessions_import_owner_fk foreign key (import_id,user_id) references public.import_runs(id,user_id) on delete cascade, constraint sleep_sessions_file_owner_fk foreign key (import_file_id,import_id,user_id) references public.import_files(id,import_id,user_id) on delete cascade, constraint sleep_sessions_owner_dedupe unique(user_id,dedupe_key), constraint sleep_sessions_time check(ended_at>started_at and duration_seconds>0), constraint sleep_sessions_hash check(source_record_hash ~ '^[0-9a-f]{64}$')
);
create table public.sleep_stages (
 id uuid primary key default gen_random_uuid(), user_id uuid not null, sleep_session_id uuid not null references public.sleep_sessions(id) on delete cascade, dedupe_key text not null, stage_code text not null, started_at timestamptz not null, ended_at timestamptz not null,
 constraint sleep_stages_owner_dedupe unique(user_id,dedupe_key), constraint sleep_stages_code check(stage_code in ('awake','light','deep','rem')), constraint sleep_stages_time check(ended_at>=started_at)
);
alter table public.sleep_sessions enable row level security; alter table public.sleep_stages enable row level security;
grant select on public.sleep_sessions, public.sleep_stages to authenticated;
create policy "Sleep sessions are readable by owner" on public.sleep_sessions for select to authenticated using ((select auth.uid())=user_id);
create policy "Sleep stages are readable by owner" on public.sleep_stages for select to authenticated using ((select auth.uid())=user_id);
