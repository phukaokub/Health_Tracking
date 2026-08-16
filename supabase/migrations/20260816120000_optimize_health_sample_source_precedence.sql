-- Keep source-precedence enforcement bounded for large JSON imports. The
-- trigger still removes overlapping legacy samples, but should not scan the
-- full canonical table for every JSON row when no legacy source exists.

create index if not exists health_samples_owner_family_type_time_idx
  on public.health_samples (user_id, source_family, source_type, started_at, ended_at);

create or replace function public.enforce_health_sample_source_precedence()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
  if new.source_family = 'huawei_legacy_xls' then
    if new.canonical_day is null then
      select (new.started_at at time zone run.timezone_candidate)::date
      into new.canonical_day
      from public.import_runs run
      where run.id = new.import_id and run.user_id = new.user_id;
    end if;
    if new.canonical_day is null or exists (
      select 1 from public.health_samples sample
      where sample.user_id = new.user_id
        and sample.source_family = 'huawei_health_json'
        and sample.source_type = new.source_type
        and sample.started_at < new.ended_at
        and sample.ended_at >= new.started_at
    ) then
      return null;
    end if;
  elsif new.source_family = 'huawei_health_json' then
    if not exists (
      select 1 from public.health_samples sample
      where sample.user_id = new.user_id
        and sample.source_family = 'huawei_legacy_xls'
    ) then
      return new;
    end if;

    delete from public.normalization_provenance provenance
    using public.health_samples sample
    where sample.user_id = new.user_id
      and sample.source_family = 'huawei_legacy_xls'
      and sample.source_type = new.source_type
      and sample.started_at < new.ended_at
      and sample.ended_at >= new.started_at
      and provenance.user_id = sample.user_id
      and provenance.import_file_id = sample.import_file_id
      and provenance.source_record_hash = sample.source_record_hash;
    delete from public.health_samples sample
    where sample.user_id = new.user_id
      and sample.source_family = 'huawei_legacy_xls'
      and sample.source_type = new.source_type
      and sample.started_at < new.ended_at
      and sample.ended_at >= new.started_at;
  end if;
  return new;
end;
$$;

