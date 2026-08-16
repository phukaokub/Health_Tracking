-- Step 6 summary contract. Aggregates are owner-scoped, bounded, and value-safe
-- for a non-clinical wellness dashboard. Raw source paths and payloads never
-- enter this response.

create index if not exists sleep_sessions_owner_time_idx
  on public.sleep_sessions (user_id, started_at desc);
create index if not exists activities_owner_time_idx
  on public.activities (user_id, started_at desc);
create index if not exists workout_sessions_owner_time_idx
  on public.workout_sessions (user_id, started_at desc);

create or replace function public.summary_api_snapshot(p_window_days integer default 7)
returns jsonb
language plpgsql
stable
security invoker
set search_path = ''
as $$
declare
  v_user_id uuid := (select auth.uid());
  v_timezone text;
  v_end_day date;
  v_start_day date;
  v_import_id uuid;
  v_import_state text;
  v_import_timezone text;
  v_warning_codes text[] := '{}'::text[];
  v_verified_file_count integer := 0;
  v_skipped_file_count integer := 0;
  v_normalized_record_count bigint := 0;
begin
  if v_user_id is null or p_window_days not in (7, 28, 90) then
    raise exception using errcode = '22023', message = 'summary_window_invalid';
  end if;

  select coalesce(nullif(profile.timezone, ''), 'UTC')
    into v_timezone
  from public.profiles profile
  where profile.id = v_user_id;
  v_timezone := coalesce(v_timezone, 'UTC');
  if not exists (select 1 from pg_catalog.pg_timezone_names zone where zone.name = v_timezone) then
    v_timezone := 'UTC';
  end if;

  -- The latest available canonical day makes imported historical exports
  -- useful immediately; an empty account falls back to today.
  select max(day) into v_end_day
  from (
    select (sample.started_at at time zone v_timezone)::date as day
    from public.health_samples sample where sample.user_id = v_user_id
    union all
    select (session.started_at at time zone v_timezone)::date
    from public.sleep_sessions session where session.user_id = v_user_id
    union all
    select (activity.started_at at time zone v_timezone)::date
    from public.activities activity where activity.user_id = v_user_id
    union all
    select (workout.started_at at time zone v_timezone)::date
    from public.workout_sessions workout where workout.user_id = v_user_id
  ) available_days;
  v_end_day := coalesce(v_end_day, (now() at time zone v_timezone)::date);
  v_start_day := v_end_day - (p_window_days - 1);

  select run.id, run.state, run.timezone_candidate,
         coalesce(job.warning_codes, '{}'::text[]),
         coalesce(job.normalized_record_count, 0)
    into v_import_id, v_import_state, v_import_timezone, v_warning_codes,
         v_normalized_record_count
  from public.import_runs run
  left join public.import_jobs job
    on job.import_id = run.id and job.user_id = run.user_id
   and job.job_type = 'parse_import'
  where run.user_id = v_user_id and run.state <> 'deleted'
  order by run.created_at desc, run.id desc
  limit 1;

  if v_import_id is not null then
    select count(*) filter (where file.inclusion_state = 'verified')::integer,
           count(*) filter (where file.inclusion_state = 'skipped_duplicate')::integer
      into v_verified_file_count, v_skipped_file_count
    from public.import_files file
    where file.import_id = v_import_id and file.user_id = v_user_id;
  end if;

  return (
    with days as (
      select generate_series(v_start_day, v_end_day, interval '1 day')::date as day
    ),
    sample_days as (
      select (sample.started_at at time zone v_timezone)::date as day,
        round(coalesce(sum(sample.value) filter (where sample.source_type = 'steps'), 0))::bigint as steps,
        round(coalesce(sum(sample.value) filter (where sample.source_type = 'active_duration'), 0) / 60)::integer as active_minutes,
        count(*) filter (where sample.source_type = 'heart_rate')::bigint as heart_rate_samples,
        count(*)::bigint as sample_count
      from public.health_samples sample
      where sample.user_id = v_user_id
        and sample.started_at >= (v_start_day::timestamp at time zone v_timezone)
        and sample.started_at < ((v_end_day + 1)::timestamp at time zone v_timezone)
      group by 1
    ),
    activity_days as (
      select (activity.started_at at time zone v_timezone)::date as day,
        round(sum(activity.duration_seconds) / 60)::integer as activity_minutes
      from public.activities activity
      where activity.user_id = v_user_id
        and activity.started_at >= (v_start_day::timestamp at time zone v_timezone)
        and activity.started_at < ((v_end_day + 1)::timestamp at time zone v_timezone)
      group by 1
    ),
    sleep_days as (
      select (session.started_at at time zone v_timezone)::date as day,
        round(sum(session.duration_seconds) / 60)::integer as sleep_minutes,
        count(*)::integer as sleep_sessions
      from public.sleep_sessions session
      where session.user_id = v_user_id
        and session.started_at >= (v_start_day::timestamp at time zone v_timezone)
        and session.started_at < ((v_end_day + 1)::timestamp at time zone v_timezone)
      group by 1
    ),
    workout_days as (
      select (workout.started_at at time zone v_timezone)::date as day,
        count(*)::integer as workouts
      from public.workout_sessions workout
      where workout.user_id = v_user_id
        and workout.started_at >= (v_start_day::timestamp at time zone v_timezone)
        and workout.started_at < ((v_end_day + 1)::timestamp at time zone v_timezone)
      group by 1
    ),
    daily as (
      select days.day,
        coalesce(sample_days.steps, 0)::bigint as steps,
        coalesce(nullif(sample_days.active_minutes, 0), activity_days.activity_minutes, 0)::integer as active_minutes,
        coalesce(sleep_days.sleep_minutes, 0)::integer as sleep_minutes,
        coalesce(workout_days.workouts, 0)::integer as workouts,
        coalesce(sample_days.heart_rate_samples, 0)::bigint as heart_rate_samples,
        (coalesce(sample_days.sample_count, 0) > 0
          or sleep_days.day is not null
          or activity_days.day is not null
          or workout_days.day is not null) as data_available
      from days
      left join sample_days on sample_days.day = days.day
      left join activity_days on activity_days.day = days.day
      left join sleep_days on sleep_days.day = days.day
      left join workout_days on workout_days.day = days.day
    )
    select jsonb_build_object(
      'window_days', p_window_days,
      'timezone', v_timezone,
      'coverage', jsonb_build_object(
        'first_day', min(daily.day) filter (where daily.data_available),
        'last_day', max(daily.day) filter (where daily.data_available),
        'days_with_data', count(*) filter (where daily.data_available),
        'window_start', v_start_day,
        'window_end', v_end_day
      ),
      'quality', jsonb_build_object(
        'import_state', coalesce(v_import_state, 'empty'),
        'import_timezone', v_import_timezone,
        'verified_file_count', v_verified_file_count,
        'skipped_duplicate_file_count', v_skipped_file_count,
        'normalized_record_count', v_normalized_record_count,
        'warning_codes', to_jsonb(v_warning_codes),
        'source_families', coalesce((
          select jsonb_agg(families.source_family order by families.source_family)
          from (
            select distinct file.source_family
            from public.import_files file
            where file.import_id = v_import_id and file.user_id = v_user_id
              and file.inclusion_state in ('verified', 'skipped_duplicate')
          ) families
        ), '[]'::jsonb)
      ),
      'metrics', coalesce((
        select jsonb_agg(jsonb_build_object(
          'day', daily.day,
          'steps', daily.steps,
          'active_minutes', daily.active_minutes,
          'sleep_minutes', daily.sleep_minutes,
          'workouts', daily.workouts,
          'heart_rate_samples', daily.heart_rate_samples,
          'data_available', daily.data_available
        ) order by daily.day)
        from daily
      ), '[]'::jsonb)
    )
    from daily
  );
end;
$$;

revoke all on function public.summary_api_snapshot(integer) from public, anon;
grant execute on function public.summary_api_snapshot(integer) to authenticated;
