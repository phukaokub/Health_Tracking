alter table public.health_samples drop constraint health_samples_unit_check;
alter table public.health_samples add constraint health_samples_unit_check check (unit in (
  'bpm', 'count', 'metres', 'seconds', 'milliseconds', 'degrees_celsius',
  'percent', 'kilocalories', 'source_score'
));

alter table public.normalization_provenance
  add column source_unit text not null default 'unknown';
alter table public.normalization_provenance
  add constraint normalization_provenance_source_unit_length check (char_length(source_unit) between 1 and 64);
