export const REPORT_RANGES = [7, 28, 90] as const;
export const REPORT_OPTIONS = [...REPORT_RANGES, "latest"] as const;
export type ReportRange = (typeof REPORT_OPTIONS)[number];

export const GOAL_DEFINITIONS = [
  {
    metric: "steps",
    label: "Daily steps",
    unit: "steps",
    cadence: "daily",
    helper: "A simple daily movement target.",
    inputStep: "1",
    inputMin: "1",
    inputMax: "100000",
  },
  {
    metric: "active_minutes",
    label: "Active minutes",
    unit: "minutes",
    cadence: "daily",
    helper: "Minutes of active time each day.",
    inputStep: "1",
    inputMin: "1",
    inputMax: "1440",
  },
  {
    metric: "workouts",
    label: "Workout frequency",
    unit: "workouts",
    cadence: "weekly",
    helper: "Planned workouts in a week.",
    inputStep: "1",
    inputMin: "1",
    inputMax: "21",
  },
  {
    metric: "sleep_duration",
    label: "Sleep duration",
    unit: "hours",
    cadence: "daily",
    helper: "A nightly sleep duration target.",
    inputStep: "0.25",
    inputMin: "1",
    inputMax: "24",
  },
  {
    metric: "bedtime_consistency",
    label: "Bedtime consistency",
    unit: "percent",
    cadence: "weekly",
    helper: "The share of nights that stay close to your planned bedtime.",
    inputStep: "1",
    inputMin: "1",
    inputMax: "100",
  },
] as const;

export type GoalMetric = (typeof GOAL_DEFINITIONS)[number]["metric"];

export type Goal = {
  id: string;
  metric: GoalMetric;
  target: number;
  unit: string;
  cadence: "daily" | "weekly";
  active: boolean;
  started_on: string;
  ended_on: string | null;
  created_at: string;
  updated_at: string;
};

export type ReportDay = {
  date: string;
  steps: number;
  active_minutes: number;
  calories: number;
  distance_metres: number;
  average_heart_rate: number | null;
  resting_heart_rate: number | null;
  sleep_hours: number;
  sleep_session_count: number;
  activity_minutes: number;
  activity_count: number;
  workout_count: number;
  workout_minutes: number;
  workout_distance_metres: number;
  workout_calories: number;
  record_count: number;
};

export type ReportCoverage = {
  steps: boolean;
  active_minutes: boolean;
  sleep: boolean;
  activity: boolean;
  workouts: boolean;
  heart_rate: boolean;
};

export type ReportData = {
  timezone: string;
  start_date: string;
  end_date: string;
  available_range: { start_date: string | null; end_date: string | null };
  days: ReportDay[];
  coverage: ReportCoverage;
  all_time_coverage: ReportCoverage;
};

export type LatestImport = {
  id: string;
  state: string;
  job_state: string | null;
  parser_version: string | null;
  parser_version_target: string | null;
  source_kind: string;
  timezone_candidate: string | null;
  total_file_count: number;
  created_at: string;
  updated_at: string;
  source_families: string[];
  warnings: string[];
  normalized_record_count: number;
  legacy_quality: {
    inserted_metric_count: number;
    conflict_metric_count: number;
    excluded_sheet_count: number;
    unknown_sheet_count: number;
    ambiguous_cell_count: number;
  } | null;
};

export type SummaryData = {
  timezone: string;
  timezoneCandidate: string | null;
  latestImport: LatestImport | null;
  report: ReportData;
};
