-- Step 6: owner-scoped goals and bounded daily report reads.
-- Report data is derived from normalized rows at request time. No raw source,
-- ECG/RRI, GPS, or device identifiers are introduced.

create table public.goals (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  metric text not null,
  target numeric not null,
  unit text not null,
  cadence text not null,
  active boolean not null default true,
  started_on date not null default current_date,
  ended_on date,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint goals_metric_check check (metric in (
    'steps', 'active_minutes', 'workouts', 'sleep_duration', 'bedtime_consistency'
  )),
  constraint goals_target_check check (target > 0 and target <= 1000000),
  constraint goals_unit_check check (unit in ('steps', 'minutes', 'workouts', 'hours', 'percent')),
  constraint goals_cadence_check check (cadence in ('daily', 'weekly')),
  constraint goals_dates_check check (ended_on is null or ended_on >= started_on)
);

create unique index goals_one_active_per_metric_idx
  on public.goals (user_id, metric)
  where active;
create index goals_owner_updated_idx
  on public.goals (user_id, updated_at desc);

alter table public.goals enable row level security;

grant select, insert, update, delete on public.goals to authenticated;

create policy "Goals are readable by owner"
  on public.goals for select to authenticated
  using ((select auth.uid()) = user_id);
create policy "Goals are insertable by owner"
  on public.goals for insert to authenticated
  with check ((select auth.uid()) = user_id);
create policy "Goals are updateable by owner"
  on public.goals for update to authenticated
  using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);
create policy "Goals are deletable by owner"
  on public.goals for delete to authenticated
  using ((select auth.uid()) = user_id);

create trigger goals_set_updated_at
before update on public.goals
for each row execute function public.set_updated_at();

create or replace function public.get_wellness_report(
  p_start_date date,
  p_end_date date,
  p_timezone text default 'UTC'
)
returns jsonb
language plpgsql
stable
security invoker
set search_path = ''
as $$
declare
  v_user_id uuid := (select auth.uid());
  v_timezone text := coalesce(nullif(trim(p_timezone), ''), 'UTC');
  v_available_start date;
  v_available_end date;
begin
  if v_user_id is null then
    raise exception using errcode = '42501', message = 'authentication_required';
  end if;
  if p_start_date is null or p_end_date is null
    or p_end_date < p_start_date
    or p_end_date > p_start_date + 89 then
    raise exception using errcode = '22023', message = 'report_range_invalid';
  end if;

  if not exists (
    select 1 from pg_catalog.pg_timezone_names where name = v_timezone
  ) then
    v_timezone := 'UTC';
  end if;

  select min(period_day), max(period_day)
    into v_available_start, v_available_end
  from (
    select (sample.started_at at time zone v_timezone)::date as period_day
    from public.health_samples sample
    where sample.user_id = v_user_id
    union all
    select (sleep.ended_at at time zone v_timezone)::date
    from public.sleep_sessions sleep
    where sleep.user_id = v_user_id
    union all
    select (activity.started_at at time zone v_timezone)::date
    from public.activities activity
    where activity.user_id = v_user_id
    union all
    select (workout.started_at at time zone v_timezone)::date
    from public.workout_sessions workout
    where workout.user_id = v_user_id
  ) periods;

  return (
    with days as (
      select generate_series(p_start_date, p_end_date, interval '1 day')::date as day
    ), sample_daily as (
      select
        (sample.started_at at time zone v_timezone)::date as day,
        sum(sample.value) filter (where sample.source_type = 'steps' and sample.unit = 'count') as steps,
        sum(sample.value) filter (where sample.source_type = 'active_duration' and sample.unit = 'seconds') / 60 as active_minutes,
        sum(sample.value) filter (where sample.source_type = 'calories' and sample.unit = 'kilocalories') as calories,
        sum(sample.value) filter (where sample.source_type = 'distance' and sample.unit = 'metres') as distance_metres,
        round(avg(sample.value) filter (where sample.source_type = 'heart_rate' and sample.unit = 'bpm'), 1) as average_heart_rate,
        round(avg(sample.value) filter (where sample.source_type = 'resting_heart_rate' and sample.unit = 'bpm'), 1) as resting_heart_rate,
        count(*)::integer as sample_count
      from public.health_samples sample
      where sample.user_id = v_user_id
        and sample.started_at >= (p_start_date::timestamp at time zone v_timezone)
        and sample.started_at < ((p_end_date + 1)::timestamp at time zone v_timezone)
      group by 1
    ), sleep_daily as (
      select
        (sleep.ended_at at time zone v_timezone)::date as day,
        sum(sleep.duration_seconds)::integer as sleep_seconds,
        count(*)::integer as sleep_session_count
      from public.sleep_sessions sleep
      where sleep.user_id = v_user_id
        and sleep.ended_at >= (p_start_date::timestamp at time zone v_timezone)
        and sleep.ended_at < ((p_end_date + 1)::timestamp at time zone v_timezone)
      group by 1
    ), activity_daily as (
      select
        (activity.started_at at time zone v_timezone)::date as day,
        sum(activity.duration_seconds)::integer as activity_seconds,
        count(*)::integer as activity_count
      from public.activities activity
      where activity.user_id = v_user_id
        and activity.started_at >= (p_start_date::timestamp at time zone v_timezone)
        and activity.started_at < ((p_end_date + 1)::timestamp at time zone v_timezone)
      group by 1
    ), workout_daily as (
      select
        (workout.started_at at time zone v_timezone)::date as day,
        count(*)::integer as workout_count,
        sum(workout.duration_seconds)::integer as workout_seconds,
        sum(workout.distance_metres) as workout_distance_metres,
        sum(workout.energy_kilocalories) as workout_calories
      from public.workout_sessions workout
      where workout.user_id = v_user_id
        and workout.started_at >= (p_start_date::timestamp at time zone v_timezone)
        and workout.started_at < ((p_end_date + 1)::timestamp at time zone v_timezone)
      group by 1
    )
    select jsonb_build_object(
      'timezone', v_timezone,
      'start_date', p_start_date,
      'end_date', p_end_date,
      'available_range', jsonb_build_object(
        'start_date', v_available_start,
        'end_date', v_available_end
      ),
      'days', coalesce((
        select jsonb_agg(jsonb_build_object(
          'date', days.day,
          'steps', coalesce(sample.steps, 0),
          'active_minutes', coalesce(sample.active_minutes, 0),
          'calories', coalesce(sample.calories, 0),
          'distance_metres', coalesce(sample.distance_metres, 0),
          'average_heart_rate', sample.average_heart_rate,
          'resting_heart_rate', sample.resting_heart_rate,
          'sleep_hours', coalesce(sleep.sleep_seconds, 0) / 3600.0,
          'sleep_session_count', coalesce(sleep.sleep_session_count, 0),
          'activity_minutes', coalesce(activity.activity_seconds, 0) / 60.0,
          'activity_count', coalesce(activity.activity_count, 0),
          'workout_count', coalesce(workout.workout_count, 0),
          'workout_minutes', coalesce(workout.workout_seconds, 0) / 60.0,
          'workout_distance_metres', coalesce(workout.workout_distance_metres, 0),
          'workout_calories', coalesce(workout.workout_calories, 0),
          'record_count', coalesce(sample.sample_count, 0)
        ) order by days.day)
        from days
        left join sample_daily sample on sample.day = days.day
        left join sleep_daily sleep on sleep.day = days.day
        left join activity_daily activity on activity.day = days.day
        left join workout_daily workout on workout.day = days.day
      ), '[]'::jsonb),
      'coverage', jsonb_build_object(
        'steps', exists (
          select 1 from public.health_samples sample
          where sample.user_id = v_user_id and sample.source_type = 'steps'
            and sample.started_at >= (p_start_date::timestamp at time zone v_timezone)
            and sample.started_at < ((p_end_date + 1)::timestamp at time zone v_timezone)
        ),
        'active_minutes', exists (
          select 1 from public.health_samples sample
          where sample.user_id = v_user_id and sample.source_type = 'active_duration'
            and sample.started_at >= (p_start_date::timestamp at time zone v_timezone)
            and sample.started_at < ((p_end_date + 1)::timestamp at time zone v_timezone)
        ),
        'sleep', exists (
          select 1 from public.sleep_sessions sleep
          where sleep.user_id = v_user_id
            and sleep.ended_at >= (p_start_date::timestamp at time zone v_timezone)
            and sleep.ended_at < ((p_end_date + 1)::timestamp at time zone v_timezone)
        ),
        'activity', exists (
          select 1 from public.activities activity
          where activity.user_id = v_user_id
            and activity.started_at >= (p_start_date::timestamp at time zone v_timezone)
            and activity.started_at < ((p_end_date + 1)::timestamp at time zone v_timezone)
        ),
        'workouts', exists (
          select 1 from public.workout_sessions workout
          where workout.user_id = v_user_id
            and workout.started_at >= (p_start_date::timestamp at time zone v_timezone)
            and workout.started_at < ((p_end_date + 1)::timestamp at time zone v_timezone)
        ),
        'heart_rate', exists (
          select 1 from public.health_samples sample
          where sample.user_id = v_user_id and sample.source_type in ('heart_rate', 'resting_heart_rate')
            and sample.started_at >= (p_start_date::timestamp at time zone v_timezone)
            and sample.started_at < ((p_end_date + 1)::timestamp at time zone v_timezone)
        )
      ),
      'all_time_coverage', jsonb_build_object(
        'steps', exists (
          select 1 from public.health_samples sample
          where sample.user_id = v_user_id and sample.source_type = 'steps'
        ),
        'active_minutes', exists (
          select 1 from public.health_samples sample
          where sample.user_id = v_user_id and sample.source_type = 'active_duration'
        ),
        'sleep', exists (select 1 from public.sleep_sessions sleep where sleep.user_id = v_user_id),
        'activity', exists (select 1 from public.activities activity where activity.user_id = v_user_id),
        'workouts', exists (select 1 from public.workout_sessions workout where workout.user_id = v_user_id),
        'heart_rate', exists (
          select 1 from public.health_samples sample
          where sample.user_id = v_user_id and sample.source_type in ('heart_rate', 'resting_heart_rate')
        )
      )
    )
  );
end;
$$;

revoke all on function public.get_wellness_report(date, date, text) from public, anon;
grant execute on function public.get_wellness_report(date, date, text) to authenticated;
