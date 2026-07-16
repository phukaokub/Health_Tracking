# Step 4 source, metric, and exclusion matrix

Status: proposed for product/privacy approval. This document contains only sanitized schema-level observations; it must never contain copied personal records, values, paths, identifiers, ECG/RRI samples, or GPS points.

## Decision rules

- JSON is the Step 4 primary source. Legacy XLS is Step 5 and may fill approved historical gaps only.
- Unknown source types are counted and warned, not guessed into a metric.
- Canonical conversion preserves source-family/type code, parser version, unit-conversion version, timezone-resolution method, and hashes needed for dedupe/provenance.
- Raw object payloads are streamed and discarded. No catch-all JSON column may retain unknown records.
- ECG is session-summary only. Raw waveform and RRI are discarded before persistence.
- Workout routes/GPS are excluded by default. Summary distance/duration/pace may be retained when independently present.
- Empty/unrelated agreement, service, purchase, ranking, social, advertisement, and account files are excluded.

## Approved mapping proposal

| Source family | Canonical metric/entity | Destination | Canonical unit/shape | Dedupe identity inputs | Warnings / exclusions | Approval |
| --- | --- | --- | --- | --- | --- | --- |
| Health detail | Heart rate | `health_samples` | bpm point/range | type, source record hash/ID, timestamp range, device, value hash | Reject impossible/non-numeric values; no interpretation | Proposed |
| Health detail | Resting heart rate | `health_samples` | bpm daily/point | type, date/time, device, value hash | Distinguish from generic HR; unknown semantics warned | Proposed |
| Health detail | HRV | `health_samples` | milliseconds | type, timestamp range, device, value hash | Do not infer RMSSD/SDNN when source does not identify it | Proposed |
| Health detail | Stress | `health_samples` | Huawei source-scale score | type, timestamp, device, value hash | Preserve scale/version; no clinical label | Proposed |
| Health detail | Skin temperature | `health_samples` | degrees Celsius | type, timestamp, device, value hash | Convert only recognized unit; no fever claim | Proposed |
| Health detail | SpO2 when present | `health_samples` | percent | type, timestamp, device, value hash | No respiratory/medical interpretation | Proposed |
| Health detail | Sleep aggregate/detail | `sleep_sessions`, `sleep_stages` | UTC bounds, seconds, stage enum | session/source ID hash, bounds, device | Unknown stage retained as warning code, not raw label | Proposed |
| Health detail | Steps | `health_samples`, later daily rollup | count | type, interval/day, device/source, value hash | Prevent overlapping legacy/extended type double count | Proposed |
| Health detail | Calories | `health_samples` | kilocalories | type, interval, device/source, value hash | Recognized unit conversion only | Proposed |
| Health detail | Distance | `health_samples` | metres | type, interval, device/source, value hash | No route geometry | Proposed |
| Health detail | Floors | `health_samples` | count | type, interval, device/source, value hash | Fractional/negative rejected | Proposed |
| Health detail | Exercise intensity | `health_samples` | source-scale/code + seconds | type, interval, device/source | Unknown intensity code warned | Proposed |
| Health detail | Active/exercise duration | `health_samples` | seconds | type, interval, device/source, value hash | Negative/overflow rejected | Proposed |
| Sample sequence | Detailed sleep session | `sleep_sessions`, `sleep_stages` | session/stage ranges | source session hash, bounds, device | Reconcile overlapping detail deterministically | Proposed |
| Sample sequence | ECG session summary | `ecg_sessions` | timestamp, duration, device, safe source status | session ID hash, timestamp, device | Drop waveform, RRI, interpretation text, raw arrays | Proposed |
| Sport per minute | Activity samples | `activities` / `health_samples` | minute interval, counts/distance/calories/duration | workout/source ID, minute, metric, device | Avoid double count with workout aggregate | Proposed |
| Motion path | Workout summary | `workout_sessions` | type, bounds, seconds, metres, kcal, pace summaries | workout/source ID hash, bounds, device | GPS points/polylines excluded; decimal-map repair allowlist only | Proposed |
| Motion path | Pace/part-time maps | Derived workout summary only | bounded aggregate fields | workout ID + repaired map key/value hash | Do not persist full maps unless later explicitly approved | Proposed |
| Any | Device reference | `devices` | sanitized model/category and stable hash | owner + normalized device fingerprint hash | No serial, MAC, advertising ID, or raw identifier | Proposed |
| Any | Unknown type/file | none | warning/count only | source family + type code hash | No payload retention and no best-effort guessing | Proposed |

## Explicitly excluded in Step 4

| Category | Handling | Reason / future gate |
| --- | --- | --- |
| Raw ECG waveform and RRI arrays | Drop before canonical persistence; count exclusion | Non-clinical scope and high sensitivity; interpretation is prohibited |
| GPS points, route polyline, precise location | Drop by default; retain only non-route workout summaries | Location privacy; opt-in design requires a separate change/consent model |
| Agreement, service, purchase, ranking, social/account metadata | Exclude file/record | Unrelated to wellness outcome and increases privacy surface |
| Advertisements, recommendations, device logs, crash/debug payloads | Exclude | Not health metrics; may contain identifiers or private diagnostics |
| Unknown JSON fields/records | Count and warn; do not store catch-all payload | Prevent accidental sensitive-data retention |
| Empty files and exact duplicates | Mark skipped/excluded | No canonical effect |
| Legacy XLS | Defer to Step 5 | Requires allowlist and JSON precedence rules |

## Timezone precedence proposal

| Priority | Evidence | Resolution | Warning condition |
| --- | --- | --- | --- |
| 1 | Explicit offset/UTC timestamp in record | Convert directly to UTC; preserve offset minutes | Invalid/range error |
| 2 | Approved device/export offset associated with record | Convert and record source | Conflicting offsets |
| 3 | Import timezone candidate/profile IANA zone | Resolve local timestamp with named zone | Ambiguous/nonexistent local time |
| 4 | No trustworthy timezone | Reject temporal record or retain date-only summary where semantically valid | `timezone_unresolved` |

## Unit conversion proposal

| Quantity | Canonical unit | Accepted input examples | Rejection/warning |
| --- | --- | --- | --- |
| Duration | seconds | milliseconds/seconds/minutes when source code identifies unit | Unknown unit, overflow, negative |
| Distance | metres | metres/kilometres when identified | Unknown unit, negative |
| Energy | kilocalories | kcal/kJ when identified | Unknown unit, negative |
| Temperature | degrees Celsius | C/F when identified | Unknown unit, implausible parse (no clinical claim) |
| Heart rate | bpm | bpm | Non-numeric/negative/out-of-domain source error |
| HRV | milliseconds | ms | Unknown HRV statistic or unit |
| SpO2 | percent | percent/fraction when source explicitly distinguishes | Outside source domain |
| Count | integer count | steps/floors/events | Fractional where prohibited, negative |

## User approval required

- Approve the proposed destinations and metric coverage.
- Approve that ECG waveform/RRI and GPS routes are discarded, not merely hidden.
- Approve unknown-type behavior: warning/count only, no catch-all storage.
- Approve timezone precedence and whether unresolved date-only summaries may be retained.
- Approve stress/intensity as source-scale wellness data without clinical interpretation.
- Approve the short raw-part recovery window in the Step 4 plan before hosted worker enablement.

## Change control

Any newly discovered source type, unit, motion repair field, ECG/GPS behavior, or canonical destination requires a reviewed matrix update plus fixtures and migration impact. Never extend mappings from a real user value observed in logs or screenshots.
