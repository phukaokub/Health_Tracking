import { createClient } from "@/lib/supabase/server";

import {
  GOAL_DEFINITIONS,
  REPORT_RANGES,
  type Goal,
  type GoalMetric,
  type LatestImport,
  type ReportCoverage,
  type ReportData,
  type ReportDay,
  type ReportRange,
  type SummaryData,
} from "./types";

type Result<T> =
  | { status: "ok"; data: T }
  | { status: "unauthorized" }
  | { status: "error" };

type UnknownRecord = Record<string, unknown>;

export async function getReport(range: ReportRange): Promise<Result<ReportData>> {
  const supabase = await createClient();
  const { data: authData } = await supabase.auth.getUser();
  if (!authData.user) return { status: "unauthorized" };

  const { data: profile, error: profileError } = await supabase
    .from("profiles")
    .select("timezone")
    .eq("id", authData.user.id)
    .maybeSingle();
  if (profileError) return { status: "error" };

  const timezone = validTimeZone(typeof profile?.timezone === "string" ? profile.timezone : "UTC");
  const endDate = todayInTimeZone(timezone);
  if (range === "latest") return getLatestReport(supabase, endDate, timezone);
  const startDate = addDays(endDate, -(range - 1));
  return queryReport(supabase, startDate, endDate, timezone);
}

async function getLatestReport(
  supabase: Awaited<ReturnType<typeof createClient>>,
  today: string,
  timezone: string,
): Promise<Result<ReportData>> {
  const probe = await queryReport(supabase, addDays(today, -(REPORT_RANGES[2] - 1)), today, timezone);
  if (probe.status !== "ok") return probe;
  const window = latestImportedWindow(probe.data.available_range);
  return window ? queryReport(supabase, window.start_date, window.end_date, timezone) : probe;
}

export function latestImportedWindow(availableRange: ReportData["available_range"]): { start_date: string; end_date: string } | null {
  const startDate = dateValue(availableRange.start_date);
  const endDate = dateValue(availableRange.end_date);
  if (!startDate || !endDate || startDate > endDate) return null;
  const maximumStart = addDays(endDate, -(REPORT_RANGES[2] - 1));
  return { start_date: startDate > maximumStart ? startDate : maximumStart, end_date: endDate };
}

export async function getSummaryData(): Promise<Result<SummaryData>> {
  const supabase = await createClient();
  const { data: authData } = await supabase.auth.getUser();
  if (!authData.user) return { status: "unauthorized" };

  const { data: profile, error: profileError } = await supabase
    .from("profiles")
    .select("timezone")
    .eq("id", authData.user.id)
    .maybeSingle();
  if (profileError) return { status: "error" };

  const timezone = validTimeZone(typeof profile?.timezone === "string" ? profile.timezone : "UTC");
  const endDate = todayInTimeZone(timezone);
  const startDate = addDays(endDate, -(REPORT_RANGES[2] - 1));
  const reportResult = await queryReport(supabase, startDate, endDate, timezone);
  if (reportResult.status !== "ok") return reportResult;

  const [runsResult, filesResult, jobsResult, qualityResult] = await Promise.all([
    supabase
      .from("import_runs")
      .select("id, state, source_kind, timezone_candidate, total_file_count, created_at, updated_at")
      .in("state", ["completed", "completed_with_warnings"])
      .order("created_at", { ascending: false })
      .limit(10),
    supabase
      .from("import_files")
      .select("import_id, source_family, inclusion_state")
      .in("inclusion_state", ["verified", "uploaded"]),
    supabase
      .from("import_jobs")
      .select("import_id, state, warning_codes, normalized_record_count")
      .eq("job_type", "parse_import")
      .order("updated_at", { ascending: false })
      .limit(10),
    supabase
      .from("legacy_xls_quality_reports")
      .select("import_id, inserted_metric_count, conflict_metric_count, excluded_sheet_count, unknown_sheet_count, ambiguous_cell_count"),
  ]);

  if (runsResult.error || filesResult.error || jobsResult.error || qualityResult.error) {
    return { status: "error" };
  }

  const latest = runsResult.data?.[0];
  let latestImport: LatestImport | null = null;
  if (latest) {
    const latestFiles = (filesResult.data ?? []).filter((file) => file.import_id === latest.id);
    const latestJob = (jobsResult.data ?? []).find((job) => job.import_id === latest.id);
    const quality = (qualityResult.data ?? []).find((report) => report.import_id === latest.id);
    latestImport = {
      id: latest.id,
      state: latest.state,
      source_kind: latest.source_kind,
      timezone_candidate: latest.timezone_candidate,
      total_file_count: latest.total_file_count,
      created_at: latest.created_at,
      updated_at: latest.updated_at,
      source_families: [...new Set(latestFiles.map((file) => file.source_family).filter(Boolean))],
      warnings: safeWarningCodes(latestJob?.warning_codes),
      normalized_record_count: numberValue(latestJob?.normalized_record_count),
      legacy_quality: quality
        ? {
            inserted_metric_count: numberValue(quality.inserted_metric_count),
            conflict_metric_count: numberValue(quality.conflict_metric_count),
            excluded_sheet_count: numberValue(quality.excluded_sheet_count),
            unknown_sheet_count: numberValue(quality.unknown_sheet_count),
            ambiguous_cell_count: numberValue(quality.ambiguous_cell_count),
          }
        : null,
    };
  }

  return {
    status: "ok",
    data: {
      timezone,
      timezoneCandidate: latestImport?.timezone_candidate ?? null,
      latestImport,
      report: reportResult.data,
    },
  };
}

export async function getGoals(): Promise<Result<Goal[]>> {
  const supabase = await createClient();
  const { data: authData } = await supabase.auth.getUser();
  if (!authData.user) return { status: "unauthorized" };

  const { data, error } = await supabase
    .from("goals")
    .select("id, metric, target, unit, cadence, active, started_on, ended_on, created_at, updated_at")
    .eq("active", true)
    .order("metric");
  if (error) return { status: "error" };

  const allowedMetrics = new Set<GoalMetric>(GOAL_DEFINITIONS.map((definition) => definition.metric));
  const goals = (data ?? []).flatMap((goal) => {
    if (!allowedMetrics.has(goal.metric as GoalMetric)) return [];
    return [{
      id: goal.id,
      metric: goal.metric as GoalMetric,
      target: numberValue(goal.target),
      unit: typeof goal.unit === "string" ? goal.unit : "",
      cadence: goal.cadence === "weekly" ? "weekly" : "daily",
      active: Boolean(goal.active),
      started_on: typeof goal.started_on === "string" ? goal.started_on : "",
      ended_on: typeof goal.ended_on === "string" ? goal.ended_on : null,
      created_at: typeof goal.created_at === "string" ? goal.created_at : "",
      updated_at: typeof goal.updated_at === "string" ? goal.updated_at : "",
    } satisfies Goal];
  });
  return { status: "ok", data: goals };
}

async function queryReport(
  supabase: Awaited<ReturnType<typeof createClient>>,
  startDate: string,
  endDate: string,
  timezone: string,
): Promise<Result<ReportData>> {
  const { data, error } = await supabase.rpc("get_wellness_report", {
    p_start_date: startDate,
    p_end_date: endDate,
    p_timezone: timezone,
  });
  if (error) return { status: "error" };
  const parsed = parseReport(data);
  return parsed ? { status: "ok", data: parsed } : { status: "error" };
}

function parseReport(value: unknown): ReportData | null {
  if (!isRecord(value)) return null;
  const available = isRecord(value.available_range) ? value.available_range : {};
  const days = Array.isArray(value.days) ? value.days.flatMap(parseDay) : [];
  const coverage = parseCoverage(value.coverage);
  const allTimeCoverage = parseCoverage(value.all_time_coverage);
  const startDate = dateValue(value.start_date);
  const endDate = dateValue(value.end_date);
  const timezone = typeof value.timezone === "string" && value.timezone ? value.timezone : "UTC";
  if (!startDate || !endDate) return null;
  return {
    timezone,
    start_date: startDate,
    end_date: endDate,
    available_range: {
      start_date: dateValue(available.start_date),
      end_date: dateValue(available.end_date),
    },
    days,
    coverage,
    all_time_coverage: allTimeCoverage,
  };
}

function parseDay(value: unknown): ReportDay[] {
  if (!isRecord(value)) return [];
  const date = dateValue(value.date);
  if (!date) return [];
  return [{
    date,
    steps: numberValue(value.steps),
    active_minutes: numberValue(value.active_minutes),
    calories: numberValue(value.calories),
    distance_metres: numberValue(value.distance_metres),
    average_heart_rate: nullableNumber(value.average_heart_rate),
    resting_heart_rate: nullableNumber(value.resting_heart_rate),
    sleep_hours: numberValue(value.sleep_hours),
    sleep_session_count: numberValue(value.sleep_session_count),
    activity_minutes: numberValue(value.activity_minutes),
    activity_count: numberValue(value.activity_count),
    workout_count: numberValue(value.workout_count),
    workout_minutes: numberValue(value.workout_minutes),
    workout_distance_metres: numberValue(value.workout_distance_metres),
    workout_calories: numberValue(value.workout_calories),
    record_count: numberValue(value.record_count),
  }];
}

function parseCoverage(value: unknown): ReportCoverage {
  const record = isRecord(value) ? value : {};
  return {
    steps: Boolean(record.steps),
    active_minutes: Boolean(record.active_minutes),
    sleep: Boolean(record.sleep),
    activity: Boolean(record.activity),
    workouts: Boolean(record.workouts),
    heart_rate: Boolean(record.heart_rate),
  };
}

function safeWarningCodes(value: unknown): string[] {
  if (!Array.isArray(value)) return [];
  return value.filter((code): code is string => typeof code === "string" && /^[a-z0-9_]{3,80}$/.test(code)).slice(0, 32);
}

function isRecord(value: unknown): value is UnknownRecord {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function numberValue(value: unknown): number {
  const parsed = typeof value === "number" ? value : typeof value === "string" ? Number(value) : 0;
  return Number.isFinite(parsed) ? parsed : 0;
}

function nullableNumber(value: unknown): number | null {
  if (value === null || value === undefined) return null;
  const parsed = numberValue(value);
  return parsed === 0 && value !== 0 && value !== "0" ? null : parsed;
}

function dateValue(value: unknown): string | null {
  return typeof value === "string" && /^\d{4}-\d{2}-\d{2}$/.test(value) ? value : null;
}

function validTimeZone(value: string): string {
  try {
    new Intl.DateTimeFormat("en-US", { timeZone: value }).format();
    return value;
  } catch {
    return "UTC";
  }
}

function todayInTimeZone(timezone: string): string {
  const parts = new Intl.DateTimeFormat("en-US", {
    timeZone: timezone,
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
  }).formatToParts(new Date());
  const values = Object.fromEntries(parts.map((part) => [part.type, part.value]));
  return `${values.year}-${values.month}-${values.day}`;
}

function addDays(date: string, days: number): string {
  const value = new Date(`${date}T00:00:00Z`);
  value.setUTCDate(value.getUTCDate() + days);
  return value.toISOString().slice(0, 10);
}
