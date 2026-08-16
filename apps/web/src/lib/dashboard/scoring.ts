import type { Goal, GoalMetric, ReportData, ReportDay } from "./types";

export const SCORE_VERSION = "score-v1";

export const SCORE_WEIGHTS = {
  sleep: 30,
  activity: 30,
  recovery_cardio: 25,
  goal_consistency: 15,
} as const;

export const SCORE_RULES = {
  minimumCoveredDays: 7,
  sleepTargetHours: 8,
  defaultStepsTarget: 7500,
  defaultActiveMinutesTarget: 22,
  defaultWorkoutsPerWeek: 3,
  trendDeltaPoints: 5,
  minimumTrendCoveredDays: 3,
} as const;

type ScoreKey = keyof typeof SCORE_WEIGHTS;

export type ScoreComponent = {
  key: ScoreKey;
  label: string;
  weight: number;
  score: number | null;
  coverage: number;
  evidence: string;
};

export type GoalTrend = {
  status: "improving" | "stable" | "declining" | "insufficient";
  startScore: number | null;
  endScore: number | null;
  change: number | null;
  evidence: string;
};

export type ScoreSuggestion = {
  key: string;
  text: string;
};

export type WellnessScore = {
  version: string;
  window: { start_date: string; end_date: string; days: number };
  total: number | null;
  coverage: number;
  components: ScoreComponent[];
  trend: GoalTrend;
  suggestions: ScoreSuggestion[];
  safety: string;
};

export function calculateWellnessScore(report: ReportData, goals: Goal[]): WellnessScore {
  const components = [
    scoreSleep(report),
    scoreActivity(report, goals),
    scoreRecoveryCardio(report, goals),
    scoreGoalConsistency(report.days, goals),
  ];
  const available = components.filter((component) => component.score !== null);
  const availableWeight = available.reduce((sum, component) => sum + component.weight, 0);
  const weightedTotal = availableWeight
    ? available.reduce((sum, component) => sum + (component.score ?? 0) * component.weight, 0) / availableWeight
    : null;
  const trend = calculateGoalTrend(report, goals);

  return {
    version: SCORE_VERSION,
    window: { start_date: report.start_date, end_date: report.end_date, days: report.days.length },
    total: weightedTotal === null ? null : rounded(weightedTotal),
    coverage: Math.round(availableWeight),
    components,
    trend,
    suggestions: buildSuggestions(components, trend, goals.length),
    safety: "This is a personal wellness summary based on the selected data window, not a medical assessment.",
  };
}

function scoreSleep(report: ReportData): ScoreComponent {
  const days = report.days.filter((day) => day.sleep_session_count > 0 && day.sleep_hours > 0);
  const coverage = coveragePercent(days.length, report.days.length);
  if (!report.coverage.sleep || days.length < SCORE_RULES.minimumCoveredDays) {
    return unavailableComponent("sleep", "Sleep", coverage, `${days.length} covered nights; at least ${SCORE_RULES.minimumCoveredDays} are needed.`);
  }
  const average = averageOf(days.map((day) => day.sleep_hours));
  return availableComponent("sleep", "Sleep", clamp(average / SCORE_RULES.sleepTargetHours * 100), coverage, `${days.length} covered nights; average compared with an ${SCORE_RULES.sleepTargetHours}-hour reference.`);
}

function scoreActivity(report: ReportData, goals: Goal[]): ScoreComponent {
  const stepsGoal = targetFor(goals, "steps") ?? SCORE_RULES.defaultStepsTarget;
  const activeMinutesGoal = targetFor(goals, "active_minutes") ?? SCORE_RULES.defaultActiveMinutesTarget;
  const days = report.days.filter((day) => day.steps > 0 || day.active_minutes > 0);
  const coverage = coveragePercent(days.length, report.days.length);
  if ((!report.coverage.steps && !report.coverage.active_minutes) || days.length < SCORE_RULES.minimumCoveredDays) {
    return unavailableComponent("activity", "Activity", coverage, `${days.length} covered movement days; at least ${SCORE_RULES.minimumCoveredDays} are needed.`);
  }
  const dailyScores = days.map((day) => {
    const values: number[] = [];
    if (day.steps > 0) values.push(clamp(day.steps / stepsGoal * 100));
    if (day.active_minutes > 0) values.push(clamp(day.active_minutes / activeMinutesGoal * 100));
    return averageOf(values);
  });
  return availableComponent("activity", "Activity", averageOf(dailyScores), coverage, `${days.length} covered movement days using steps and active minutes.`);
}

function scoreRecoveryCardio(report: ReportData, goals: Goal[]): ScoreComponent {
  const workoutDays = report.days.filter((day) => day.workout_count > 0);
  const coverage = coveragePercent(workoutDays.length, report.days.length);
  if (!report.coverage.workouts || workoutDays.length < 2) {
    return unavailableComponent("recovery_cardio", "Cardio & recovery context", coverage, `${workoutDays.length} workout days; more activity coverage is needed for this component.`);
  }
  const target = targetFor(goals, "workouts") ?? SCORE_RULES.defaultWorkoutsPerWeek;
  const expected = target * (report.days.length / 7);
  const score = clamp(sum(workoutDays.map((day) => day.workout_count)) / expected * 100);
  return availableComponent("recovery_cardio", "Cardio & recovery context", score, coverage, `${workoutDays.length} workout days compared with a ${target}-per-week reference; no heart-rate interpretation is used.`);
}

function scoreGoalConsistency(days: ReportDay[], goals: Goal[]): ScoreComponent {
  const supported = goals
    .map((goal) => goalConsistencyForGoal(days, goal, SCORE_RULES.minimumCoveredDays))
    .filter((value): value is { score: number; coverage: number } => value !== null);
  const coverage = goals.length ? Math.round(averageOf(supported.map((value) => value.coverage))) : 0;
  if (!supported.length) {
    return unavailableComponent("goal_consistency", "Goal consistency", coverage, goals.length ? "Active goals do not have enough supported data in this window." : "Set a goal before goal consistency can be calculated.");
  }
  return availableComponent("goal_consistency", "Goal consistency", averageOf(supported.map((value) => value.score)), coverage, `${supported.length} active goal${supported.length === 1 ? "" : "s"} have enough data in this window.`);
}

function calculateGoalTrend(report: ReportData, goals: Goal[]): GoalTrend {
  if (report.days.length !== 28 || !goals.length) {
    return { status: "insufficient", startScore: null, endScore: null, change: null, evidence: "A descriptive trend needs a 28-day window and at least one active goal." };
  }
  const midpoint = Math.floor(report.days.length / 2);
  const startScore = goalWindowScore(report.days.slice(0, midpoint), goals);
  const endScore = goalWindowScore(report.days.slice(midpoint), goals);
  if (startScore === null || endScore === null) {
    return { status: "insufficient", startScore, endScore, change: null, evidence: "Each half of the 28-day window needs enough covered goal data." };
  }
  const change = rounded(endScore - startScore);
  const status = change >= SCORE_RULES.trendDeltaPoints ? "improving" : change <= -SCORE_RULES.trendDeltaPoints ? "declining" : "stable";
  return { status, startScore, endScore, change, evidence: `Compared the first and last 14 days of ${report.start_date} to ${report.end_date}; this is descriptive, not a forecast.` };
}

function goalWindowScore(days: ReportDay[], goals: Goal[]): number | null {
  const values = goals
    .map((goal) => goalConsistencyForGoal(days, goal, SCORE_RULES.minimumTrendCoveredDays))
    .filter((value): value is { score: number; coverage: number } => value !== null);
  return values.length ? rounded(averageOf(values.map((value) => value.score))) : null;
}

function goalConsistencyForGoal(days: ReportDay[], goal: Goal, minimumDays: number): { score: number; coverage: number } | null {
  const metric = goal.metric;
  if (metric === "bedtime_consistency") return null;
  if (metric === "workouts") {
    const coveredDays = days.filter((day) => day.workout_count > 0).length;
    if (coveredDays < Math.min(2, minimumDays)) return null;
    const expected = goal.target * (days.length / 7);
    return { score: clamp(sum(days.map((day) => day.workout_count)) / expected * 100), coverage: coveragePercent(coveredDays, days.length) };
  }
  const values = days.flatMap((day) => {
    const value = goalValue(day, metric);
    return value > 0 ? [value] : [];
  });
  if (values.length < minimumDays) return null;
  return { score: averageOf(values.map((value) => clamp(value / goal.target * 100))), coverage: coveragePercent(values.length, days.length) };
}

function goalValue(day: ReportDay, metric: Exclude<GoalMetric, "workouts" | "bedtime_consistency">): number {
  if (metric === "steps") return day.steps;
  if (metric === "active_minutes") return day.active_minutes;
  return day.sleep_hours;
}

function buildSuggestions(components: ScoreComponent[], trend: GoalTrend, goalCount: number): ScoreSuggestion[] {
  const suggestions: ScoreSuggestion[] = [];
  for (const component of components) {
    if (component.score === null) {
      suggestions.push({ key: `${component.key}-coverage`, text: `${component.label} is not scored yet: ${component.evidence}` });
    } else if (component.score < 70) {
      suggestions.push({ key: `${component.key}-focus`, text: `${component.label} is below the working reference in the ${SCORE_VERSION} calculation. Review the ${component.evidence.toLowerCase()}` });
    }
  }
  if (!goalCount) suggestions.push({ key: "set-goal", text: "Set one personal goal to make goal consistency and its 28-day trend available." });
  if (trend.status === "improving") suggestions.push({ key: "trend-improving", text: "Your goal completion is trending upward across the selected 28-day window." });
  if (trend.status === "declining") suggestions.push({ key: "trend-declining", text: "Your goal completion is trending downward across the selected 28-day window; review the underlying days before changing a target." });
  return suggestions.slice(0, 4);
}

function availableComponent(key: ScoreKey, label: string, score: number, coverage: number, evidence: string): ScoreComponent {
  return { key, label, weight: SCORE_WEIGHTS[key], score: rounded(score), coverage, evidence };
}

function unavailableComponent(key: ScoreKey, label: string, coverage: number, evidence: string): ScoreComponent {
  return { key, label, weight: SCORE_WEIGHTS[key], score: null, coverage, evidence };
}

function targetFor(goals: Goal[], metric: GoalMetric): number | null {
  const goal = goals.find((item) => item.metric === metric && item.active);
  return goal && goal.target > 0 ? goal.target : null;
}

function coveragePercent(covered: number, total: number): number {
  return total ? Math.round(covered / total * 100) : 0;
}

function averageOf(values: number[]): number {
  return values.length ? sum(values) / values.length : 0;
}

function sum(values: number[]): number { return values.reduce((total, value) => total + value, 0); }
function clamp(value: number): number { return Math.max(0, Math.min(100, value)); }
function rounded(value: number): number { return Math.round(value * 10) / 10; }
